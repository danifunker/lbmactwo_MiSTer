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

#include "../supervisor_bench/bench_types.h"
#include "../supervisor_bench/jsonl_writer.h"
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

/* Paint helpers — same signatures as supervisor_bench/font_ascii.c. */
extern void paint_string(u32 row, u32 col_byte, const char *s, u32 max_chars);
extern void paint_progress(u32 idx, u32 total);

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

/* Parameter block for _Read / _Write. */
typedef struct {
    u8  pad_qlink[12];
    u16 qtype;             /* offset 12 */
    u16 io_trap;           /* offset 14 */
    u16 io_result;         /* offset 16 */
    u8  pad_name[4];
    u16 io_vrefnum;        /* offset 22 */
    u16 io_refnum;         /* offset 24 */
    u8  io_versnum;
    u8  io_permssn;
    u8  pad_misc[6];
    u32 io_buffer;         /* offset 32 */
    u32 io_req_count;      /* offset 36 */
    u32 io_act_count;      /* offset 40 */
    u16 io_pos_mode;       /* offset 44 */
    u32 io_pos_offset;     /* offset 46 */
    u8  pad_rest[30];
} ParamBlock;

static ParamBlock g_pb;

/* The _Read and _Write traps are A002 / A003. Call them by stuffing
 * the trap word inline in assembly. Inputs: A0 = ParamBlock. Outputs:
 * ioResult set in the PB; D0 = ioResult also returned. */
static i16 trap_read(ParamBlock *pb)
{
    register i16  r asm("d0");
    register ParamBlock *p asm("a0") = pb;
    asm volatile (".word 0xA002\n"
                  : "=d"(r)
                  : "a"(p)
                  : "cc", "memory");
    return r;
}

static i16 trap_write(ParamBlock *pb)
{
    register i16  r asm("d0");
    register ParamBlock *p asm("a0") = pb;
    asm volatile (".word 0xA003\n"
                  : "=d"(r)
                  : "a"(p)
                  : "cc", "memory");
    return r;
}

static void pb_init(ParamBlock *pb, u32 buf, u32 offset, u32 length)
{
    u32 *w = (u32 *)pb;
    u32  n = sizeof(*pb) / 4;
    while (n--) *w++ = 0;
    pb->io_refnum     = g_handoff_refnum;
    pb->io_vrefnum    = g_handoff_drive;
    pb->io_buffer     = buf;
    pb->io_req_count  = length;
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

void bench_main(void)
{
    JwCtx ctx;
    u16 i;

    ctx.refnum      = g_handoff_refnum;
    ctx.drive       = g_handoff_drive;
    ctx.base_offset = g_results_offset;
    ctx.max_bytes   = 32 * 1024;            /* same allocation as build_*.sh */
    jw_init(&g_jw, &ctx);

    paint_string(4, 4, "IOTEST: DISK I/O BENCH", 22);

    u32 mem_top = MEM_TOP;

    for (i = 0; i < g_iotest_n_sizes; i++) {
        const IoTestSize *s = &g_iotest_sizes[i];
        u32 t_us;
        i16 err;

        paint_progress(i + 1, g_iotest_n_sizes);
        paint_string(8, 4, s->label, 8);

        /* RAM check: the buffer at IOBUF_BASE must hold s->length
         * bytes. If MemTop is below the buffer end, the test can't run
         * on this Mac — emit a "skip" line and continue. The bound
         * check uses 64-bit-equivalent math via the cast so a 4 MB
         * length doesn't overflow when added to IOBUF_BASE.           */
        if ((u32)IOBUF_BASE + s->length > mem_top ||
            s->length > mem_top - (u32)IOBUF_BASE) {
            paint_string(10, 4, "SKIP RAM", 8);
            emit_skip_line(&g_jw, s, "insufficient_ram", mem_top);
            continue;
        }

        /* ----- READ ----- */
        paint_string(10, 4, "READ   ", 7);
        pb_init(&g_pb, (u32)g_io_buf, s->read_offset, s->length);
        timer_start();
        err = trap_read(&g_pb);
        t_us = timer_elapsed_us();
        emit_read_line(&g_jw, s, t_us, err);

        /* ----- WRITE + READBACK ----- */
        paint_string(10, 4, "WRITE  ", 7);
        fill_pattern(g_io_buf, s->length, (u8)i);
        pb_init(&g_pb, (u32)g_io_buf, s->write_offset, s->length);
        timer_start();
        err = trap_write(&g_pb);
        t_us = timer_elapsed_us();

        u32 wr_us = t_us; i16 wr_err = err;

        paint_string(10, 4, "VERIFY ", 7);
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
    }

    paint_string(10, 4, "DONE       ", 11);
    jw_flush(&g_jw);
}
