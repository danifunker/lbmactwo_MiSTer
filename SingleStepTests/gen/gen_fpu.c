/*
 * FPU test corpus generator for cpu_fpu/ bench.
 *
 * Each test exercises one FPU instruction round-trip through the integrated
 * TG68K + mc68881_top Verilator bench. The only TG68K coprocessor microcode
 * paths that currently work are FMOVE.L Dn↔FPn (load + store integer); ALU
 * ops (FADD, FSUB, FMUL, FNEG, FABS, FINT, FINTRZ) need no extra microcode
 * because they're reg-to-reg with operands already in FP regs.
 *
 * Test program template:
 *   MOVEQ #op_a,D0         ; load op_a into D0
 *   FMOVE.L D0,FP0         ; load FP0 from D0 (cp_xfer_to)
 *   [if dyadic:
 *     MOVEQ #op_b,D0       ; load op_b into D0
 *     FMOVE.L D0,FP1       ; load FP1 from D0
 *   ]
 *   <test_instruction>     ; FADD FP1,FP0 / FNEG FP0,FP0 / etc.
 *   FMOVE.L FP0,D{rreg}    ; store result back to Dn (cp_xfer_from)
 *   STOP #$2700            ; halt
 *
 * Bench checks D{rreg} == expected after halt.
 *
 * Operand range is MOVEQ's signed 8-bit (-128..127). FMUL operands further
 * restricted so the product fits int32.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

/* ---------- Tiny seeded RNG (xorshift32) ----------------------------- */
static uint32_t g_rng = 0xBEEFC0DEu;
static uint32_t r32(void) {
    uint32_t x = g_rng;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    return g_rng = x;
}
/* Random signed byte in MOVEQ range. */
static int8_t r_moveq(void) { return (int8_t)(r32() & 0xFF); }
/* Random signed byte limited to ±limit. */
static int8_t r_moveq_lim(int limit) {
    int8_t v = (int8_t)(r32() % (2 * limit + 1));
    return v - (int8_t)limit;
}

/* ---------- M68881 op encodings ------------------------------------- */
/* Reg-to-reg ALU (opclass 000) ext word:
 *   bits 15-13 = 000
 *   bits 12-10 = src FP register
 *   bits  9-7  = dst FP register
 *   bits  6-0  = opmode (M68881 native cpGEN opmode)
 */
#define OPMODE_FADD   0x22
#define OPMODE_FSUB   0x28
#define OPMODE_FMUL   0x23
#define OPMODE_FDIV   0x20
#define OPMODE_FSQRT  0x04
#define OPMODE_FNEG   0x1A
#define OPMODE_FABS   0x18
#define OPMODE_FINT   0x01
#define OPMODE_FINTRZ 0x03

/* ext for monadic op (FNEG/FABS/...): src and dst both = fp, opmode. */
static uint16_t ext_monadic_fp(int fp, uint8_t opmode) {
    return (uint16_t)(((fp & 7) << 10) | ((fp & 7) << 7) | opmode);
}
/* ext for dyadic reg-to-reg: dst = dst op src; src=FPm, dst=FPn. */
static uint16_t ext_dyadic(int fpm_src, int fpn_dst, uint8_t opmode) {
    return (uint16_t)(((fpm_src & 7) << 10) | ((fpn_dst & 7) << 7) | opmode);
}

/* MOVEQ #imm,D0: opcode 0x7000 | (D0<<9) | imm = 0x7000 | imm (D0=0). */
static uint16_t moveq_d0(int8_t imm) { return (uint16_t)(0x7000 | (uint8_t)imm); }
/* FMOVE.{size} D0,FPn: opword $F200 | EA(D0=0) = $F200; ext = opclass 010
 * (EA→FPn), src fmt in bits 12-10 (L=0, S=1, X=2, P=3, W=4, D=5, B=6),
 * dst FPn (n<<7), opmode FMOVE (0x00). */
#define FMT_L 0
#define FMT_S 1
#define FMT_X 2
#define FMT_W 4
#define FMT_B 6
static uint16_t fmove_size_d0_fpn(int n, int fmt) {
    return (uint16_t)(0x4000 | ((fmt & 7) << 10) | ((n & 7) << 7));
}
/* (Convenience helpers for individual sizes are inlined at call sites via
 * fmove_size_d0_fpn(n, FMT_*); no per-size wrappers needed.) */
/* (FMOVE.L FPn,Dx opword/ext are built in emit_program below using
 *  fmove_l_fpn_dn_opw and the dst_fp parameter.) */

/* ---------- JSON emission ------------------------------------------- */
typedef struct {
    const char* name;
    int      has_b;        /* 1 = dyadic (also load src_fp) */
    int      op_a;         /* op_a value -> dst_fp */
    int      op_b;         /* op_b value -> src_fp (dyadic only) */
    int      dst_fp;       /* FPn that holds op_a / receives result (0..7) */
    int      src_fp;       /* FPm that holds op_b (dyadic only) */
    uint8_t  opmode;       /* test instruction opmode */
    int      load_fmt;     /* FMT_L / FMT_W / FMT_B for the FMOVE EA→FPn load */
    int      result_reg;   /* Dn that receives FMOVE.L FP{dst_fp},Dn */
    int32_t  expected;     /* expected value of D{result_reg} */
} test_t;

static uint16_t fmove_l_fpn_dn_opw(int n) {
    /* FMOVE.L FPn,Dx opword = $F200 | Dx-mode-reg = $F200 | n (mode 0). */
    return (uint16_t)(0xF200 | (n & 7));
}

static void emit_program(FILE* f, const test_t* t) {
    fprintf(f, "[");
    int first = 1;
    #define BW(w) do { \
        if (!first) fprintf(f, ","); \
        fprintf(f, "%u,%u", ((unsigned)(w) >> 8) & 0xFF, (unsigned)(w) & 0xFF); \
        first = 0; \
    } while (0)

    /* Load op_a into FP{dst_fp} using configured size. */
    BW(moveq_d0((int8_t)t->op_a));
    BW(0xF200);
    BW(fmove_size_d0_fpn(t->dst_fp, t->load_fmt));
    /* If dyadic, load op_b into FP{src_fp} (same size). */
    if (t->has_b) {
        BW(moveq_d0((int8_t)t->op_b));
        BW(0xF200);
        BW(fmove_size_d0_fpn(t->src_fp, t->load_fmt));
    }
    /* Test instruction. */
    BW(0xF200);
    BW(t->has_b
       ? ext_dyadic(t->src_fp, t->dst_fp, t->opmode)
       : ext_monadic_fp(t->dst_fp, t->opmode));
    /* FMOVE.L FP{dst_fp},D{result_reg} */
    BW(fmove_l_fpn_dn_opw(t->result_reg));
    BW((uint16_t)(0x6000 | ((t->dst_fp & 7) << 7)));
    /* STOP #$2700 */
    BW(0x4E72);
    BW(0x2700);
    #undef BW
    fprintf(f, "]");
}

static void emit_test_clean(FILE* f, int is_first, const test_t* t) {
    if (!is_first) fprintf(f, ",\n");
    fprintf(f, "  {\n");
    fprintf(f, "    \"name\":\"%s\",\n", t->name);
    fprintf(f, "    \"op_a\":%d,", t->op_a);
    if (t->has_b) fprintf(f, "\"op_b\":%d,", t->op_b);
    fprintf(f, "\n    \"program\":");
    emit_program(f, t);
    fprintf(f, ",\n    \"result_reg\":%d,\n", t->result_reg);
    fprintf(f, "    \"expected\":%d\n", t->expected);
    fprintf(f, "  }");
}

/* Pick a random FP register 0..7. */
static int pick_fp(void) { return (int)(r32() & 7); }
/* Pick a random Dn 1..7 (avoid D0, used as temp during FMOVE loads). */
static int pick_result_reg(void) { return 1 + (int)(r32() % 7); }
/* Pick two distinct FP registers 0..7. */
static void pick_two_fp(int* a, int* b) {
    *a = pick_fp();
    do { *b = pick_fp(); } while (*b == *a);
}

/* ---------- Per-op generators --------------------------------------- */
static const char* fmt_str(int fmt) {
    switch (fmt) { case FMT_L: return "L"; case FMT_W: return "W";
                   case FMT_B: return "B"; case FMT_S: return "S";
                   default: return "?"; }
}

static int gen_monadic_sized(FILE* f, int is_first, const char* op_name,
                             uint8_t opmode, int (*compute)(int),
                             int load_fmt, int count) {
    for (int i = 0; i < count; ++i) {
        int8_t a = r_moveq();
        int    fp = pick_fp();
        int    rr = pick_result_reg();
        test_t t = {
            .name = NULL, .has_b = 0, .op_a = a, .op_b = 0,
            .dst_fp = fp, .src_fp = fp,
            .opmode = opmode, .load_fmt = load_fmt,
            .result_reg = rr, .expected = compute(a),
        };
        char nm[100];
        snprintf(nm, sizeof(nm), "%s.X (load.%s) FP%d (#%d) -> D%d #%03d",
                 op_name, fmt_str(load_fmt), fp, a, rr, i);
        t.name = nm;
        emit_test_clean(f, is_first && i == 0, &t);
    }
    return count;
}

static int gen_dyadic_sized(FILE* f, int is_first, const char* op_name,
                            uint8_t opmode, int (*compute)(int, int),
                            int limit_a, int limit_b, int load_fmt, int count) {
    for (int i = 0; i < count; ++i) {
        int8_t a = r_moveq_lim(limit_a);
        int8_t b = r_moveq_lim(limit_b);
        int    dst, src;
        pick_two_fp(&dst, &src);
        int    rr = pick_result_reg();
        test_t t = {
            .name = NULL, .has_b = 1, .op_a = a, .op_b = b,
            .dst_fp = dst, .src_fp = src,
            .opmode = opmode, .load_fmt = load_fmt,
            .result_reg = rr, .expected = compute(a, b),
        };
        char nm[120];
        snprintf(nm, sizeof(nm),
                 "%s (load.%s) FP%d,FP%d (%d,%d) -> D%d #%03d",
                 op_name, fmt_str(load_fmt), src, dst, a, b, rr, i);
        t.name = nm;
        emit_test_clean(f, is_first && i == 0, &t);
    }
    return count;
}

/* Default-size (.L) wrappers for compatibility with existing call sites. */
static int gen_monadic(FILE* f, int is_first, const char* op_name,
                       uint8_t opmode, int (*compute)(int), int count) {
    return gen_monadic_sized(f, is_first, op_name, opmode, compute, FMT_L, count);
}
static int gen_dyadic(FILE* f, int is_first, const char* op_name,
                      uint8_t opmode, int (*compute)(int, int),
                      int limit_a, int limit_b, int count) {
    return gen_dyadic_sized(f, is_first, op_name, opmode, compute,
                            limit_a, limit_b, FMT_L, count);
}

/* Generator for FSQRT with perfect-square inputs only (so result fits int). */
static int gen_fsqrt(FILE* f, int is_first, int count) {
    /* Perfect squares 0..121: 0, 1, 4, 9, 16, 25, 36, 49, 64, 81, 100, 121 */
    static const int squares[] = {0, 1, 4, 9, 16, 25, 36, 49, 64, 81, 100, 121};
    const int N = (int)(sizeof(squares) / sizeof(squares[0]));
    for (int i = 0; i < count; ++i) {
        int a = squares[i % N];
        int fp = pick_fp();
        int rr = pick_result_reg();
        int expected;
        switch (a) {
            case 0:   expected = 0;  break;
            case 1:   expected = 1;  break;
            case 4:   expected = 2;  break;
            case 9:   expected = 3;  break;
            case 16:  expected = 4;  break;
            case 25:  expected = 5;  break;
            case 36:  expected = 6;  break;
            case 49:  expected = 7;  break;
            case 64:  expected = 8;  break;
            case 81:  expected = 9;  break;
            case 100: expected = 10; break;
            case 121: expected = 11; break;
            default:  expected = 0;  break;
        }
        test_t t = {
            .name = NULL, .has_b = 0, .op_a = a, .op_b = 0,
            .dst_fp = fp, .src_fp = fp,
            .opmode = OPMODE_FSQRT, .load_fmt = FMT_L,
            .result_reg = rr, .expected = expected,
        };
        char nm[80];
        snprintf(nm, sizeof(nm), "FSQRT.X FP%d (#%d -> %d) -> D%d #%03d",
                 fp, a, expected, rr, i);
        t.name = nm;
        emit_test_clean(f, is_first && i == 0, &t);
    }
    return count;
}

/* FDIV restricted to exact-integer divisions (op_a % op_b == 0). */
static int gen_fdiv(FILE* f, int is_first, int count) {
    int emitted = 0;
    while (emitted < count) {
        int8_t b = r_moveq_lim(10);
        if (b == 0) continue;          /* skip divide-by-zero */
        int    quot = r_moveq_lim(10);
        if (quot == 0) continue;        /* skip zero quotients (trivial) */
        int    a = (int)b * (int)quot;
        if (a < -128 || a > 127) continue;
        int    dst, src;
        pick_two_fp(&dst, &src);
        int    rr = pick_result_reg();
        test_t t = {
            .name = NULL, .has_b = 1, .op_a = a, .op_b = b,
            .dst_fp = dst, .src_fp = src,
            .opmode = OPMODE_FDIV, .load_fmt = FMT_L,
            .result_reg = rr, .expected = quot,
        };
        char nm[100];
        snprintf(nm, sizeof(nm), "FDIV FP%d,FP%d (%d/%d=%d) -> D%d #%03d",
                 src, dst, a, b, quot, rr, emitted);
        t.name = nm;
        emit_test_clean(f, is_first && emitted == 0, &t);
        emitted++;
    }
    return emitted;
}

/* Result computation helpers — int-preserving since we round-trip via .L. */
static int fneg_compute(int a)        { return -a; }
static int fabs_compute(int a)        { return a < 0 ? -a : a; }
static int fint_compute(int a)        { return a; }    /* already int */
static int fintrz_compute(int a)      { return a; }    /* truncate toward zero, already int */
static int fadd_compute(int a, int b) { return a + b; }
static int fsub_compute(int a, int b) { return a - b; }  /* FSUB FP1,FP0 = FP0 - FP1 */
static int fmul_compute(int a, int b) { return a * b; }

/* ---------------------------------------------------------------------- */
int main(int argc, char** argv) {
    const char* outpath = (argc > 1) ? argv[1] : "fpu_corpus.json";
    if (argc > 2) g_rng = (uint32_t)strtoul(argv[2], NULL, 0);

    FILE* f = fopen(outpath, "w");
    if (!f) { perror(outpath); return 1; }
    fprintf(f, "[\n");

    int total = 0;
    int first = 1;
    const int N = 40;

    total += gen_monadic(f, first, "FNEG",   OPMODE_FNEG,   fneg_compute,   N); first = 0;
    total += gen_monadic(f, first, "FABS",   OPMODE_FABS,   fabs_compute,   N);
    total += gen_monadic(f, first, "FINT",   OPMODE_FINT,   fint_compute,   N);
    total += gen_monadic(f, first, "FINTRZ", OPMODE_FINTRZ, fintrz_compute, N);
    /* Dyadic with bounded operands so int32 result fits.
     * FADD/FSUB: ±127 each, sum ±254. FMUL: ±10 each, product ±100. */
    total += gen_dyadic (f, first, "FADD",   OPMODE_FADD, fadd_compute, 127, 127, N);
    total += gen_dyadic (f, first, "FSUB",   OPMODE_FSUB, fsub_compute, 127, 127, N);
    total += gen_dyadic (f, first, "FMUL",   OPMODE_FMUL, fmul_compute,  10,  10, N);
    /* FSQRT: perfect squares only (so result fits int). */
    total += gen_fsqrt  (f, first, N);
    /* FDIV: exact integer divisions only (a % b == 0). */
    total += gen_fdiv   (f, first, N);

    /* ---- Size-variant load tests --------------------------------------
     * Same ops loaded via FMOVE.W and FMOVE.B (instead of FMOVE.L) to
     * exercise the FPU's sign-extension paths from short integers. For
     * MOVEQ-range operands (-128..127), the FP value after a sized load
     * should match the .L round-trip, so the same compute() functions
     * are valid. Fewer tests per op since coverage focus is on the load
     * path, not the ALU.                                                 */
    const int M = 16;
    total += gen_monadic_sized(f, first, "FNEG",   OPMODE_FNEG,   fneg_compute,   FMT_W, M);
    total += gen_monadic_sized(f, first, "FNEG",   OPMODE_FNEG,   fneg_compute,   FMT_B, M);
    total += gen_monadic_sized(f, first, "FABS",   OPMODE_FABS,   fabs_compute,   FMT_W, M);
    total += gen_monadic_sized(f, first, "FABS",   OPMODE_FABS,   fabs_compute,   FMT_B, M);
    total += gen_dyadic_sized (f, first, "FADD",   OPMODE_FADD, fadd_compute, 127, 127, FMT_W, M);
    total += gen_dyadic_sized (f, first, "FADD",   OPMODE_FADD, fadd_compute, 127, 127, FMT_B, M);
    total += gen_dyadic_sized (f, first, "FMUL",   OPMODE_FMUL, fmul_compute,  10,  10, FMT_W, M);
    total += gen_dyadic_sized (f, first, "FMUL",   OPMODE_FMUL, fmul_compute,  10,  10, FMT_B, M);

    fprintf(f, "\n]\n");
    fclose(f);
    printf("Wrote %s (%d tests, seed=0x%08X)\n", outpath, total, g_rng);
    return 0;
}
