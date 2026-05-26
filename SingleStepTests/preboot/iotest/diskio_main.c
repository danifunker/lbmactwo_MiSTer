/* diskio_main.c — disk I/O bench, supervisor-mode.
 *
 * Per test size we run two measurements:
 *
 *   READ:
 *     _Read N bytes from the pre-baked file /Read_<label>. We time the
 *     _Read trap end-to-end with VIA1 T2 (microsecond resolution).
 *
 *   WRITE:
 *     _Write N bytes of a known pattern to /Write_<label>'s scratch
 *     region, then _Read it back, CRC-check the round-trip, and time
 *     each leg separately so writeback-cache effects don't get rolled
 *     into a single number.
 *
 * Results are emitted as JSONL via the supervisor_bench JsonlWriter:
 *
 *   {"size":"1KB","len":1024,"op":"read","us":NNN,"err":0}
 *   {"size":"1KB","len":1024,"op":"write","us":NNN,"err":0,"verified":1,
 *    "readback_us":NNN}
 *
 * 'verified' is 1 only when the readback bytes match the pattern we
 * wrote. 'err' is the ioResult from the _Read/_Write trap (0 = noErr).
 *
 * The screen displays a single progress line per test as it runs so a
 * hang or driver reset is attributable to a specific size+op. */

#include "bench_types.h"
#include "jsonl_writer.h"
#include "sizes.h"
#include "timing.h"

/* Provided by payload_entry.s — same convention as the CPU bench. */
extern i16 g_handoff_refnum;
extern i16 g_handoff_drive;

/* /Results.jsonl byte offset within the partition. Patched in at
 * image-build time by patch_offsets.py.
 *
 * The marker + the offset live in a single non-const struct so the
 * linker keeps them adjacent in .data. The patch script greps for the
 * 8-byte marker and writes the u32 in the slot that immediately
 * follows. __packed__ guarantees no padding between marker[8] and
 * offset(u32) — both fields are u8/u32 with natural alignment 4, but
 * being explicit prevents future struct-layout surprises. */
/* volatile on both fields keeps the compiler from constant-propagating
 * the placeholder into bench_main()'s callsite, and from discarding the
 * marker as unreferenced. Non-static so external visibility further
 * blocks dead-store elimination. */
struct __attribute__((__packed__)) iotest_results_slot {
    volatile char marker[8];
    volatile u32  offset;
};
struct iotest_results_slot g_results_slot = {
    { 'I','O','R','E','S','L','T','_' }, 0xDEADBEEFu
};

#define g_results_offset (g_results_slot.offset)

/* Paint helpers — same signature as supervisor_bench/font_ascii.c. */
extern void paint_string(u32 row, u32 col_byte, const char *s, u32 max_chars);

/* I/O buffer pinned to a fixed high address — NOT in .bss.
 *
 * Two reasons for the fixed address:
 *   1. A 4 MB BSS array would force the linker to lay symbols (and
 *      our stack) several megabytes past where we load. On a Mac with
 *      less RAM than that, the BSS-zero or stack pointer setup would
 *      bus-error before bench_main() runs.
 *   2. We want to vary the *usable* buffer extent at runtime based on
 *      MemTop, not at link time based on a worst-case define.
 *
 * Placing the buffer at $200000 (2 MB) leaves the 0..2 MB region for
 * payload code + stack, with a comfortable 1 MB+ gap above the stack
 * top ($100000). Tests whose buffer would extend past MemTop are
 * skipped at runtime. */
#define IOBUF_BASE 0x00200000u

/* Mac low-mem MemTop ($0108) = byte just past last RAM byte. ROM
 * populates this during early boot, well before our boot stub runs. */
#define MEM_TOP (*(volatile u32 *)0x00000108)

static u8 * const g_io_buf = (u8 *)IOBUF_BASE;

/* IOParam parameter block for _Read / _Write. Field offsets must
 * match Inside Macintosh: Files exactly — the Device Manager reads
 * the trap arguments from these byte offsets regardless of how we
 * choose to name them in C.
 *
 *   0  ioQLink       (long)
 *   4  ioQType       (word)
 *   6  ioTrap        (word)
 *   8  ioCmdAddr     (long)
 *  12  ioCompletion  (long)
 *  16  ioResult      (word)         ← signed; 0 = noErr
 *  18  ioNamePtr     (long)
 *  22  ioVRefNum     (word)
 *  24  ioRefNum      (word)         ← driver refnum (signed)
 *  26  ioVersNum     (byte)
 *  27  ioPermssn     (byte)
 *  28  ioMisc        (long)         ← 4 BYTES, not 6 (earlier bug)
 *  32  ioBuffer      (long)
 *  36  ioReqCount    (long)
 *  40  ioActCount    (long)
 *  44  ioPosMode     (word)
 *  46  ioPosOffset   (long)
 *
 * Total 50 bytes through ioPosOffset. Padded to PB_SIZE (80) so the
 * struct length matches what `jsonl_writer.c` already uses. */
typedef struct {
    u8  pad_qlink[12];     /* offsets 0..11 (qlink + qtype + ioTrap + ioCmdAddr) */
    u32 io_completion;     /* offset 12 */
    u16 io_result;         /* offset 16 */
    u32 io_name_ptr;       /* offset 18 */
    u16 io_vrefnum;        /* offset 22 */
    u16 io_refnum;         /* offset 24 */
    u8  io_versnum;        /* offset 26 */
    u8  io_permssn;        /* offset 27 */
    u32 io_misc;           /* offset 28 */
    u32 io_buffer;         /* offset 32 */
    u32 io_req_count;      /* offset 36 */
    u32 io_act_count;      /* offset 40 */
    u16 io_pos_mode;       /* offset 44 */
    u32 io_pos_offset;     /* offset 46 */
    u8  pad_rest[30];      /* offsets 50..79 */
} ParamBlock;

static ParamBlock g_pb;

/* The _Read and _Write traps are A002 / A003. Call them by stuffing
 * the trap word inline in assembly. Inputs: A0 = ParamBlock. Outputs:
 * ioResult set in the PB; D0 = ioResult also returned. */
/* The _Read/_Write Device Manager traps clobber D1/D2/A1 in addition to
 * D0 (result) and A0 (param block). The earlier clobber list named only
 * "cc"/"memory", which is a latent miscompile waiting to happen: if the
 * register allocator ever keeps a live value in D1/D2/A1 across the trap
 * it gets silently corrupted. jsonl_writer.c's _Write already lists them;
 * keep these in sync. */
static i16 trap_read(ParamBlock *pb)
{
    register i16  r asm("d0");
    register ParamBlock *p asm("a0") = pb;
    asm volatile (".word 0xA002\n"
                  : "=d"(r)
                  : "a"(p)
                  : "d1", "d2", "a1", "cc", "memory");
    return r;
}

static i16 trap_write(ParamBlock *pb)
{
    register i16  r asm("d0");
    register ParamBlock *p asm("a0") = pb;
    asm volatile (".word 0xA003\n"
                  : "=d"(r)
                  : "a"(p)
                  : "d1", "d2", "a1", "cc", "memory");
    return r;
}

/* Raw block-driver transfers must be whole 512-byte sectors: the
 * Device Manager .Disk/SCSI driver does NO sub-block buffering (that is
 * the File Manager's job, and these _Read/_Write calls go straight to
 * the driver via its refnum, below the File Manager). Issuing a
 * sub-sector ioReqCount like 1 byte drives the NCR5380 + DMA path into
 * a transfer it can't satisfy — fatal on real hardware (hard reset, no
 * Sad Mac) and a no-op/loop under MAME's more forgiving SCSI model.
 *
 * Round the logical test length up to the next sector, one-sector
 * minimum, so the tiny sizes ("1B", "512B") still issue a legal count.
 * The JSONL still reports the logical s->length; only the bytes moved
 * across the bus are rounded. */
#define SECTOR_BYTES 512u
static u32 sector_round_up(u32 n)
{
    if (n == 0) return SECTOR_BYTES;
    return (n + (SECTOR_BYTES - 1u)) & ~(SECTOR_BYTES - 1u);
}

static void pb_init(ParamBlock *pb, u32 buf, u32 offset, u32 length)
{
    u32 *w = (u32 *)pb;
    u32  n = sizeof(*pb) / 4;
    while (n--) *w++ = 0;
    pb->io_refnum     = g_handoff_refnum;
    pb->io_vrefnum    = g_handoff_drive;
    pb->io_buffer     = buf;
    pb->io_req_count  = sector_round_up(length);  /* whole sectors only */
    pb->io_pos_mode   = 1;  /* fsFromStart */
    pb->io_pos_offset = offset;
}

/* Fill buf with a size-aware pattern: byte i = (i ^ (i >> 8) ^ seed) & 0xFF.
 * Cheap and changes every byte so we'd notice partial-writeback bugs. */
static void fill_pattern(u8 *buf, u32 len, u8 seed)
{
    u32 i;
    for (i = 0; i < len; i++)
        buf[i] = (u8)((i ^ (i >> 8) ^ seed) & 0xFFu);
}

static int verify_pattern(const u8 *buf, u32 len, u8 seed)
{
    u32 i;
    for (i = 0; i < len; i++)
        if (buf[i] != (u8)((i ^ (i >> 8) ^ seed) & 0xFFu))
            return 0;
    return 1;
}

/* Emit a single JSONL line marking a size as skipped because the I/O
 * buffer would extend past physical RAM. One line per skipped test so
 * downstream tools see exactly which sizes couldn't run on this Mac. */
static void emit_skip_line(JsonlWriter *jw, const IoTestSize *s,
                           const char *reason, u32 mem_top)
{
    jw_puts(jw, "{\"size\":\""); jw_puts(jw, s->label);
    jw_puts(jw, "\",\"len\":");  jw_putul(jw, s->length);
    jw_puts(jw, ",\"op\":\"skip\",\"reason\":\""); jw_puts(jw, reason);
    jw_puts(jw, "\",\"mem_top\":0x"); jw_putul(jw, mem_top);
    jw_puts(jw, ",\"iobuf_base\":0x"); jw_putul(jw, IOBUF_BASE);
    jw_puts(jw, "}\n");
    jw_commit_line(jw);
}

/* Emit one JSONL line for a read result. */
static void emit_read_line(JsonlWriter *jw, const IoTestSize *s,
                           u32 elapsed_us, i16 err)
{
    jw_puts(jw, "{\"size\":\""); jw_puts(jw, s->label);
    jw_puts(jw, "\",\"len\":");  jw_putul(jw, s->length);
    jw_puts(jw, ",\"op\":\"read\",\"us\":"); jw_putul(jw, elapsed_us);
    jw_puts(jw, ",\"err\":");    jw_putul(jw, (u32)(i32)err);
    jw_puts(jw, "}\n");
    jw_commit_line(jw);
}

/* Emit one JSONL line for a write+readback result. */
static void emit_write_line(JsonlWriter *jw, const IoTestSize *s,
                            u32 write_us, i16 write_err,
                            u32 read_us,  i16 read_err,
                            int verified)
{
    jw_puts(jw, "{\"size\":\""); jw_puts(jw, s->label);
    jw_puts(jw, "\",\"len\":");  jw_putul(jw, s->length);
    jw_puts(jw, ",\"op\":\"write\",\"us\":"); jw_putul(jw, write_us);
    jw_puts(jw, ",\"err\":");    jw_putul(jw, (u32)(i32)write_err);
    jw_puts(jw, ",\"readback_us\":"); jw_putul(jw, read_us);
    jw_puts(jw, ",\"readback_err\":"); jw_putul(jw, (u32)(i32)read_err);
    jw_puts(jw, ",\"verified\":"); jw_putul(jw, (u32)verified);
    jw_puts(jw, "}\n");
    jw_commit_line(jw);
}

static JsonlWriter g_jw;

/* paint_string takes a PIXEL row (not a character row), and glyphs are 8
 * pixels tall. LINE(n) places each visible text line on a 12-pixel grid
 * (8-pixel glyph + 4-pixel gap) so adjacent lines are clear of each other.
 *
 * Layout: one banner row + one column-header row + one result row per
 * test size, all visible at the same time so the operator can scan the
 * full pass/fail matrix without needing to remember the order.
 *
 *     LINE(0)   "IOTEST: DISK I/O BENCH"
 *     LINE(1)   "SIZE     READ     WRITE"      (column header)
 *     LINE(2)   "1B       pass     pass"        i=0
 *     LINE(3)   "512B     pass     pass"        i=1
 *     ...
 *     LINE(2+N) per-size row N
 *
 * 12 HDA sizes -> last result row at LINE(13) = pixel row 156. Well
 * within the 480-px screen (mdc824 default mode). Floppy variant runs
 * 8 sizes so it stops at LINE(9) = 108. */
#define LINE(n)         ((n) * 12u)
#define LINE_BANNER     LINE(0)
#define LINE_HEADER     LINE(1)
#define LINE_RESULT(i)  LINE(2u + (i))

/* Per-line byte-column layout (1 byte = 8 pixels on the 1bpp screen). */
#define COL_SIZE        1u    /* "1B"..."4MB"  8 cols wide */
#define COL_READ        10u   /* "pass" or "E-NN" 6 cols wide */
#define COL_WRITE       20u   /* "pass" or "FAIL" 6 cols wide (full mode) */
#define STATUS_W        6u    /* fixed width so old chars overprint cleanly */

/* Format a 6-char status cell into `out` (no NUL):
 *   err == 0  ->  "pass  "
 *   err != 0  ->  "E-NN  " or "E NNN" (signed decimal, padded to 6 chars).
 * Caller passes a 6-byte buffer; paint_string is told to render exactly 6
 * chars so a longer previous string ("....") is wiped from the cell. */
static void fmt_status(char out[STATUS_W], i16 err)
{
    u32 i;
    for (i = 0; i < STATUS_W; i++) out[i] = ' ';
    if (err == 0) { out[0]='p'; out[1]='a'; out[2]='s'; out[3]='s'; return; }
    i32 v = (i32)err;
    int neg = (v < 0);
    if (neg) v = -v;
    /* Format up to 4 digits right-justified, prefix sign before first digit. */
    u32 div_table[4] = { 1000, 100, 10, 1 };
    u32 d, started = 0, pos = 2;
    out[0] = 'E';
    out[1] = neg ? '-' : ' ';
    for (d = 0; d < 4; d++) {
        u32 digit = ((u32)v / div_table[d]) % 10;
        if (digit || started || d == 3) {
            if (pos < STATUS_W) out[pos++] = (char)('0' + digit);
            started = 1;
        }
    }
}

/* Paint one result row's fixed parts (size label + cells set to "....").
 * Called once per size before its test runs so the operator sees the row
 * appear in advance and watches the cells fill in. */
static void paint_row_skeleton(u16 i, const char *label)
{
    char dots[STATUS_W] = {'.',' ','.',' ','.',' '};
    paint_string(LINE_RESULT(i), COL_SIZE,  label, 8);
    paint_string(LINE_RESULT(i), COL_READ,  dots,  STATUS_W);
#ifndef IOTEST_READ_ONLY
    paint_string(LINE_RESULT(i), COL_WRITE, dots,  STATUS_W);
#endif
}

static void paint_cell(u16 i, u32 col, const char *six)
{
    paint_string(LINE_RESULT(i), col, six, STATUS_W);
}

void bench_main(void)
{
    JwCtx ctx;
    u16 i;
    char status[STATUS_W];

    ctx.refnum      = g_handoff_refnum;
    ctx.drive       = g_handoff_drive;
    ctx.base_offset = g_results_offset;
    ctx.max_bytes   = 32 * 1024;            /* same allocation as build_*.sh */
    jw_init(&g_jw, &ctx);

    paint_string(LINE_BANNER, COL_SIZE, "IOTEST: DISK I/O BENCH", 22);
#ifndef IOTEST_READ_ONLY
    paint_string(LINE_HEADER, COL_SIZE,  "SIZE",  4);
    paint_string(LINE_HEADER, COL_READ,  "READ",  4);
    paint_string(LINE_HEADER, COL_WRITE, "WRITE", 5);
#else
    paint_string(LINE_HEADER, COL_SIZE, "SIZE", 4);
    paint_string(LINE_HEADER, COL_READ, "READ", 4);
#endif

    u32 mem_top = MEM_TOP;

    for (i = 0; i < g_iotest_n_sizes; i++) {
        const IoTestSize *s = &g_iotest_sizes[i];
        u32 t_us;
        i16 err;

        paint_row_skeleton(i, s->label);

        /* RAM check: the buffer at IOBUF_BASE must hold s->length
         * bytes. If MemTop is below the buffer end, the test can't run
         * on this Mac — mark the row "SKIP" in both cells and continue. */
        if ((u32)IOBUF_BASE + s->length > mem_top ||
            s->length > mem_top - (u32)IOBUF_BASE) {
            paint_cell(i, COL_READ,  "SKIP  ");
#ifndef IOTEST_READ_ONLY
            paint_cell(i, COL_WRITE, "SKIP  ");
#endif
            emit_skip_line(&g_jw, s, "insufficient_ram", mem_top);
            continue;
        }

        /* ----- READ ----- */
        pb_init(&g_pb, (u32)g_io_buf, s->read_offset, s->length);
        timer_start();
        err = trap_read(&g_pb);
        t_us = timer_elapsed_us();
        emit_read_line(&g_jw, s, t_us, err);
        fmt_status(status, err); paint_cell(i, COL_READ, status);

#ifndef IOTEST_READ_ONLY
        /* ----- WRITE + READBACK ----- */
        fill_pattern(g_io_buf, s->length, (u8)i);
        pb_init(&g_pb, (u32)g_io_buf, s->write_offset, s->length);
        timer_start();
        err = trap_write(&g_pb);
        t_us = timer_elapsed_us();

        u32 wr_us = t_us; i16 wr_err = err;

        /* Clear the buffer so we know readback isn't a false match. */
        {
            u32 *w = (u32 *)g_io_buf;
            u32  n = (s->length + 3) / 4;
            while (n--) *w++ = 0;
        }
        pb_init(&g_pb, (u32)g_io_buf, s->write_offset, s->length);
        timer_start();
        err = trap_read(&g_pb);
        t_us = timer_elapsed_us();

        int ok = (err == 0) && verify_pattern(g_io_buf, s->length, (u8)i);
        emit_write_line(&g_jw, s, wr_us, wr_err, t_us, err, ok);

        /* WRITE cell shows the write-trap result, not verify -- the
         * write succeeding but verify failing is a different class of
         * failure (driver returned noErr but readback didn't match the
         * pattern) and would normally show up as a FAIL in the readback
         * leg too. Single-cell summary; full detail is in /Results.jsonl. */
        if (wr_err == 0 && !ok)      fmt_status(status, -1);  /* verify failed */
        else                          fmt_status(status, wr_err);
        paint_cell(i, COL_WRITE, status);
#endif
    }

    jw_flush(&g_jw);
}
