/* bench_main.c — supervisor-mode CPU bench.
 * Mirrors gen/cpu_test_macii.c but writes via raw sector _Write
 * instead of stdio. Runs privileged tests now (we're already supervisor).
 * hw_unsafe tests still skipped (they'd hang the machine). */

#include "bench_types.h"
#include "freestanding.h"
#include "jsonl_writer.h"
#include "tests_cpu.h"

/* Provided by payload_entry_cpu.s — handoff slot at $00041000 */
extern volatile i16 g_handoff_refnum;
extern volatile i16 g_handoff_drive;
extern u32  g_results_offset;     /* compile-time constant, set per variant */
extern u32  g_results_max_bytes;  /* compile-time constant */

/* recovery.s — VBR + longjmp-style exception escape. */
extern void install_vbr(void);
extern int invoke_test_with_recovery(u8 *entry);   /* 0 = OK, !=0 = vector */

/* Scratch buffers */
static Snapshot init_snap;
static Snapshot final_snap;
static u32 init_pc;
static u32 final_pc;
static u8  scratch_ram[CPU_SCRATCH_LEN];
static u8  prog_buffer[1024];

/* ---- Machine-code emitters (identical to cpu_test_macii.c) ---- */
static u8 *put_w(u8 *p, u16 v) { *p++=(u8)(v>>8); *p++=(u8)v; return p; }
static u8 *put_l(u8 *p, u32 v) {
    *p++=(u8)(v>>24); *p++=(u8)(v>>16);
    *p++=(u8)(v>>8);  *p++=(u8) v;       return p;
}
static u8 *emit_move_l_dn_to_abs(u8 *p, int dn, u32 addr) {
    p = put_w(p, (u16)(0x23C0 | (dn & 7))); return put_l(p, addr);
}
static u8 *emit_move_l_an_to_abs(u8 *p, int an, u32 addr) {
    p = put_w(p, (u16)(0x23C8 | (an & 7))); return put_l(p, addr);
}
static u8 *emit_movea_l_imm_to_an(u8 *p, int an, u32 imm) {
    p = put_w(p, (u16)(0x207C | ((an & 7) << 9))); return put_l(p, imm);
}
static u8 *emit_move_w_imm_to_ccr(u8 *p, u16 imm) {
    p = put_w(p, 0x44FC); return put_w(p, (u16)(imm & 0xFF));
}

static u8 *emit_state_dump(u8 *p, Snapshot *snap, int is_init)
{
    u32 base = (u32) snap;
    u32 scratch_base = (u32) &scratch_ram[0];
    int n, i;
    if (!is_init) { p = put_w(p, 0x42F9); p = put_l(p, base + 0x40); }
    for (n = 0; n < 8; n++) p = emit_move_l_an_to_abs(p, n, base + 0x20 + n * 4);
    for (n = 0; n < 8; n++) p = emit_move_l_dn_to_abs(p, n, base + 0x00 + n * 4);
    for (i = 0; i < CPU_SCRATCH_LEN / 4; i++) {
        p = put_w(p, 0x23F9);
        p = put_l(p, scratch_base + i * 4);
        p = put_l(p, base + 0x44 + i * 4);
    }
    if (is_init) { p = put_w(p, 0x42F9); p = put_l(p, base + 0x40); }
    return p;
}

static u8 *build_program(const CpuTestSpec *t)
{
    u8 *entry = prog_buffer;
    u8 *p = entry;
    int n;

    for (n = 0; n < 8; n++) p = put_w(p, (u16)(0x7000 | (n << 9)));     /* MOVEQ #0,Dn */
    for (n = 0; n < 6; n++) p = put_w(p, (u16)(0x91C8 | (n << 9) | n)); /* SUBA.L An,An */

    p = emit_movea_l_imm_to_an(p, 6, (u32) &scratch_ram[0]);
    p = emit_move_w_imm_to_ccr(p, 0);

    if (t->preload_len) { f_memcpy(p, t->preload, t->preload_len); p += t->preload_len; }
    p = emit_state_dump(p, &init_snap, 1);
    init_pc = (u32) p;
    f_memcpy(p, t->test, t->test_len);
    p += t->test_len;
    final_pc = (u32) p;
    p = emit_state_dump(p, &final_snap, 0);

    *p++ = 0x4E; *p++ = 0x75;     /* RTS */
    return entry;
}

/* 68020 instruction-cache flush. Writing CACR with bit 3 = CI
 * invalidates the entire IC; bit 0 = EI keeps it enabled. We MUST do
 * this between tests because we keep rewriting prog_buffer and the
 * CPU may execute stale cached bytes from the previous test. */
static void flush_icache(void)
{
    asm volatile (
        "moveq #9, %%d0          \n"   /* CI | EI = 0x09 */
        ".long 0x4E7B0002        \n"   /* movec d0, cacr */
        :
        :
        : "d0"
    );
}

/* Save callee-saved regs, jsr into the assembled test, restore.
 * Re-mask interrupts IMMEDIATELY on return so tests that clear the I
 * field of SR (e.g. ANDI.W #$F8FF,SR at test 180) can't trigger an
 * IRQ before our code restores SR. */
static void invoke_program(u8 *entry)
{
    asm volatile (
        "moveml %%d2-%%d7/%%a2-%%a6, -(%%sp)   \n"
        "movel  %0, %%a0                       \n"
        "jsr    (%%a0)                         \n"
        "movew  #0x2700, %%sr                  \n"
        "moveml (%%sp)+, %%d2-%%d7/%%a2-%%a6   \n"
        :
        : "g" (entry)
        : "a0", "a1", "d0", "d1", "cc", "memory"
    );
}

/* Emit one snapshot as the same JSON shape MAME emits. */
static void write_snap(JsonlWriter *w, const Snapshot *s, u32 pc)
{
    int i;
    jw_puts(w, "{\"d\":[");
    for (i = 0; i < 8; i++) { if (i) jw_putc(w, ','); jw_putul(w, s->d[i]); }
    jw_puts(w, "],\"a\":[");
    for (i = 0; i < 8; i++) { if (i) jw_putc(w, ','); jw_putul(w, s->a[i]); }
    jw_puts(w, "],\"ccr\":"); jw_putul(w, s->ccr);
    jw_puts(w, ",\"pc\":");   jw_putul(w, pc);
    jw_puts(w, ",\"ram\":[");
    for (i = 0; i < CPU_SCRATCH_LEN; i++) {
        if (i) jw_putc(w, ',');
        jw_putul(w, s->ram[i]);
    }
    jw_puts(w, "]}");
}

static void write_name(JsonlWriter *w, const char *name)
{
    jw_putc(w, '"');
    while (*name) {
        if (*name == '"' || *name == '\\') jw_putc(w, '\\');
        jw_putc(w, *name);
        name++;
    }
    jw_putc(w, '"');
}

/* Painted progress: tiny 4-digit decimal at row 56 col 4 of ScrnBase
 * so the operator sees the bench is alive. ~10 LOC of hand-rolled
 * digit drawing kept in the C side so the main asm stays small. */
extern void paint_progress(u32 idx, u32 total);

/* Provided by font_ascii.c */
extern void paint_string(u32 row, u32 col_byte, const char *s, u32 max_chars);

/* Mac low-mem Ticks counter at $016A — 60 Hz, 32-bit. Available
 * after Boot Globals init, which the ROM does before bbEntry. */
#define TICKS_ADDR 0x0000016A
static u32 read_ticks(void) {
    return *(volatile u32 *)TICKS_ADDR;
}

/* Format an unsigned decimal into a 10-char zero-padded buffer for
 * status display. Buffer must be at least 11 bytes. */
static void format_decimal(char *out, u32 v, int width) {
    char tmp[11];
    int n = 0, i;
    if (v == 0) tmp[n++] = '0';
    while (v) { tmp[n++] = (char)('0' + (v % 10)); v /= 10; }
    for (i = 0; i < width - n; i++) *out++ = ' ';
    while (n--) *out++ = tmp[n];
    *out = '\0';
}

void bench_main(void)
{
    JwCtx ctx;
    JsonlWriter w;
    u32 i;

    /* install_vbr(); */   /* TEMP DISABLED to bisect — was breaking test 1 */
    ctx.refnum      = g_handoff_refnum;
    ctx.drive       = g_handoff_drive;
    ctx.base_offset = g_results_offset;
    ctx.max_bytes   = g_results_max_bytes;
    jw_init(&w, &ctx);

    for (i = 0; i < CPU_N_TESTS; i++) {
        const CpuTestSpec *t = &g_cpu_tests[i];
        u8 *entry;
        u32 t_start, t_end;
        char buf[16];
        int skip = t->raises_exception || t->hw_unsafe;

        f_memset(&init_snap,  0, sizeof(init_snap));
        f_memset(&final_snap, 0, sizeof(final_snap));
        f_memset(scratch_ram, 0, sizeof(scratch_ram));
        init_pc = 0; final_pc = 0;

        if (t->ram_init_present)
            f_memcpy(scratch_ram, t->ram_init, CPU_SCRATCH_LEN);

        /* Show "[NNN/TTT] name" on screen at row 28 col 4. */
        format_decimal(buf, i + 1, 4);
        paint_string(28, 4, buf, 4);
        paint_string(28, 8, "/", 1);
        format_decimal(buf, CPU_N_TESTS, 4);
        paint_string(28, 9, buf, 4);
        paint_string(28, 14, " ", 1);
        paint_string(28, 15, t->name, 50);

        t_start = read_ticks();
        if (!skip) {
            paint_string(50, 4, "B", 1);
            entry = build_program(t);
            paint_string(50, 4, "F", 1);
            flush_icache();
            paint_string(50, 4, "I", 1);
            invoke_program(entry);
            paint_string(50, 4, "R", 1);
        } else {
            paint_string(50, 4, "S", 1);
        }
        t_end = read_ticks();
        paint_string(50, 4, ".", 1);

        /* Show elapsed ticks (60Hz) at row 40 col 4. */
        format_decimal(buf, t_end - t_start, 8);
        paint_string(40, 4, "T=", 2);
        paint_string(40, 6, buf, 8);
        paint_string(50, 5, "J", 1);       /* about to write JSON */

        jw_putc(&w, '{');
        jw_puts(&w, "\"name\":"); write_name(&w, t->name);
        jw_puts(&w, ",\"ticks\":"); jw_putul(&w, t_end - t_start);
        jw_puts(&w, ",\"initial\":"); write_snap(&w, &init_snap, init_pc);
        jw_puts(&w, ",\"final\":");   write_snap(&w, &final_snap, final_pc);
        jw_puts(&w, "}\n");
        /* Per-line commit was hanging the SCSI _Write after ~113 calls.
         * Skip it — full-sector flushes via jw_putc will still drive
         * one _Write per ~512 bytes of output. */
        paint_string(50, 5, "+", 1);

        if ((i & 0x0F) == 0) paint_progress(i, CPU_N_TESTS);
    }

    jw_flush(&w);
    paint_progress(CPU_N_TESTS, CPU_N_TESTS);
    paint_string(28, 4, "ALL TESTS COMPLETE", 50);
}
