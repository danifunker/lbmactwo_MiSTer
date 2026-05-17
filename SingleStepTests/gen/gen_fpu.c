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
/* MOVE.L #imm,D0: opword 0x203C, then 4-byte big-endian immediate. Used to
 * load a full 32-bit value when MOVEQ's signed-8-bit range isn't enough
 * (e.g. an IEEE single bit pattern for FMOVE.S). */
#define MOVE_L_IMM_D0 ((uint16_t)0x203C)
/* IEEE 754 single-precision bit pattern for a small integer. Uses native
 * float→bits punning; portable enough for our test generator host. */
#include <string.h>
static uint32_t int_to_ieee_single(int n) {
    float f = (float)n;
    uint32_t bits;
    memcpy(&bits, &f, 4);
    return bits;
}
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

    /* Load op_a into FP{dst_fp} using configured size. For FMT_S the
     * operand is the IEEE-single bit pattern of op_a, which needs
     * MOVE.L #imm,D0 (6 bytes) instead of MOVEQ. */
    if (t->load_fmt == FMT_S) {
        uint32_t bits_a = int_to_ieee_single(t->op_a);
        BW(MOVE_L_IMM_D0);
        BW((uint16_t)(bits_a >> 16));
        BW((uint16_t)(bits_a & 0xFFFF));
    } else {
        BW(moveq_d0((int8_t)t->op_a));
    }
    BW(0xF200);
    BW(fmove_size_d0_fpn(t->dst_fp, t->load_fmt));
    /* If dyadic, load op_b into FP{src_fp} (same size). */
    if (t->has_b) {
        if (t->load_fmt == FMT_S) {
            uint32_t bits_b = int_to_ieee_single(t->op_b);
            BW(MOVE_L_IMM_D0);
            BW((uint16_t)(bits_b >> 16));
            BW((uint16_t)(bits_b & 0xFFFF));
        } else {
            BW(moveq_d0((int8_t)t->op_b));
        }
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

/* FDIV with arbitrary integer operands, result truncated to int via
 * FINTRZ before readback. Expected = trunc(a / b) (C99 integer division
 * truncates toward zero for both signs, matching FINTRZ).            */
static int gen_fdiv_trunc(FILE* f, int is_first, int count) {
    int emitted = 0;
    while (emitted < count) {
        int8_t b = r_moveq_lim(20);
        if (b == 0) continue;
        int8_t a = r_moveq_lim(127);
        int    quot = (int)a / (int)b;
        if (quot > 127 || quot < -128) continue;  /* keep room for safety */
        int    dst, src;
        pick_two_fp(&dst, &src);
        int    rr = pick_result_reg();
        /* Program: load a→FPdst, load b→FPsrc, FDIV FPsrc,FPdst,
         *          FINTRZ FPdst,FPdst, FMOVE.L FPdst,Dn, STOP.
         * We can't express FINTRZ as a separate test entry through emit_test_clean
         * (it builds a single test instruction). So we emit a custom JSON entry. */
        char nm[120];
        snprintf(nm, sizeof(nm),
                 "FDIV+FINTRZ FP%d,FP%d (%d/%d=%d) -> D%d #%03d",
                 src, dst, (int)a, (int)b, quot, rr, emitted);
        if (!(is_first && emitted == 0)) fprintf(f, ",\n");
        fprintf(f, "  {\n");
        fprintf(f, "    \"name\":\"%s\",\n", nm);
        fprintf(f, "    \"op_a\":%d,\"op_b\":%d,\n", (int)a, (int)b);
        fprintf(f, "    \"program\":[");
        int first = 1;
        #define BW2(w) do { \
            if (!first) fprintf(f, ","); \
            fprintf(f, "%u,%u", ((unsigned)(w) >> 8) & 0xFF, (unsigned)(w) & 0xFF); \
            first = 0; \
        } while (0)
        BW2(moveq_d0(a));
        BW2(0xF200); BW2(fmove_size_d0_fpn(dst, FMT_L));
        BW2(moveq_d0(b));
        BW2(0xF200); BW2(fmove_size_d0_fpn(src, FMT_L));
        BW2(0xF200); BW2(ext_dyadic(src, dst, OPMODE_FDIV));
        BW2(0xF200); BW2(ext_monadic_fp(dst, OPMODE_FINTRZ));
        BW2((uint16_t)(0xF200 | (rr & 7)));
        BW2((uint16_t)(0x6000 | ((dst & 7) << 7)));
        BW2(0x4E72); BW2(0x2700);
        #undef BW2
        fprintf(f, "],\n");
        fprintf(f, "    \"result_reg\":%d,\n", rr);
        fprintf(f, "    \"expected\":%d\n", quot);
        fprintf(f, "  }");
        emitted++;
    }
    return emitted;
}

/* FSQRT with non-perfect-square integer inputs; truncate result via FINTRZ. */
static int gen_fsqrt_trunc(FILE* f, int is_first, int count) {
    int emitted = 0;
    while (emitted < count) {
        int  a = (int)(r32() % 128);   /* 0..127 to fit MOVEQ */
        if (a == 0) continue;
        /* trunc(sqrt(a)) via integer Newton iteration / search */
        int  s = 0;
        while ((s + 1) * (s + 1) <= a) s++;
        int  expected_trunc = s;
        int    fp = pick_fp();
        int    rr = pick_result_reg();
        char nm[120];
        snprintf(nm, sizeof(nm),
                 "FSQRT+FINTRZ FP%d (sqrt(%d)=%d) -> D%d #%03d",
                 fp, a, expected_trunc, rr, emitted);
        if (!(is_first && emitted == 0)) fprintf(f, ",\n");
        fprintf(f, "  {\n");
        fprintf(f, "    \"name\":\"%s\",\n", nm);
        fprintf(f, "    \"op_a\":%d,\n", a);
        fprintf(f, "    \"program\":[");
        int first = 1;
        #define BW3(w) do { \
            if (!first) fprintf(f, ","); \
            fprintf(f, "%u,%u", ((unsigned)(w) >> 8) & 0xFF, (unsigned)(w) & 0xFF); \
            first = 0; \
        } while (0)
        BW3(moveq_d0((int8_t)a));
        BW3(0xF200); BW3(fmove_size_d0_fpn(fp, FMT_L));
        BW3(0xF200); BW3(ext_monadic_fp(fp, OPMODE_FSQRT));
        BW3(0xF200); BW3(ext_monadic_fp(fp, OPMODE_FINTRZ));
        BW3((uint16_t)(0xF200 | (rr & 7)));
        BW3((uint16_t)(0x6000 | ((fp & 7) << 7)));
        BW3(0x4E72); BW3(0x2700);
        #undef BW3
        fprintf(f, "],\n");
        fprintf(f, "    \"result_reg\":%d,\n", rr);
        fprintf(f, "    \"expected\":%d\n", expected_trunc);
        fprintf(f, "  }");
        emitted++;
    }
    return emitted;
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

/* M68881 FPcc condition selector codes (6-bit). */
#define COND_F   0x00
#define COND_EQ  0x01
#define COND_NE  0x0E
#define COND_T   0x0F
#define COND_GT  0x12
#define COND_GE  0x13
#define COND_LT  0x14
#define COND_LE  0x15

/* Evaluate condition for integer operand pair (assuming ordered result of
 * FCMP fpm,fpn = FPn - FPm; FPCC bits reflect that). */
static int eval_cond_int(uint8_t cond, int n, int m) {
    /* fpcc: ordered comparison of FPn vs FPm. */
    int eq = (n == m), gt = (n > m), lt = (n < m);
    switch (cond) {
        case COND_F:  return 0;
        case COND_T:  return 1;
        case COND_EQ: return eq;
        case COND_NE: return !eq;
        case COND_GT: return gt;
        case COND_GE: return gt || eq;
        case COND_LT: return lt;
        case COND_LE: return lt || eq;
        default:      return 0;
    }
}

/* FCMP FPm,FPn  +  FScc.B Dx tests. Loads FPm and FPn, runs FCMP
 * (sets FPCC), then FScc.B Dx with the chosen condition. Verifies
 * Dx low byte is 0xFF or 0x00 per the condition. */
static int gen_fcmp_fscc(FILE* f, int is_first, int count) {
    static const struct { uint8_t code; const char* name; } conds[] = {
        {COND_F, "F"}, {COND_T, "T"}, {COND_EQ, "EQ"}, {COND_NE, "NE"},
        {COND_GT, "GT"}, {COND_GE, "GE"}, {COND_LT, "LT"}, {COND_LE, "LE"},
    };
    const int NC = (int)(sizeof(conds) / sizeof(conds[0]));
    for (int i = 0; i < count; ++i) {
        int8_t a = r_moveq_lim(50);
        int8_t b = r_moveq_lim(50);
        int    dst, src;
        pick_two_fp(&dst, &src);
        int    rr = pick_result_reg();
        const int     ci = (int)(r32() % NC);
        const uint8_t cond = conds[ci].code;
        const char*   cname = conds[ci].name;
        const int expected = eval_cond_int(cond, a, b);

        char nm[120];
        snprintf(nm, sizeof(nm), "FCMP+FS%s FP%d,FP%d (%d,%d) -> D%d #%03d",
                 cname, src, dst, (int)a, (int)b, rr, i);
        if (!(is_first && i == 0)) fprintf(f, ",\n");
        fprintf(f, "  {\n");
        fprintf(f, "    \"name\":\"%s\",\n", nm);
        fprintf(f, "    \"op_a\":%d,\"op_b\":%d,\n", (int)a, (int)b);
        fprintf(f, "    \"program\":[");
        int first = 1;
        #define BWf(w) do { \
            if (!first) fprintf(f, ","); \
            fprintf(f, "%u,%u", ((unsigned)(w) >> 8) & 0xFF, (unsigned)(w) & 0xFF); \
            first = 0; \
        } while (0)
        /* MOVEQ #0,Drr — clear Drr high bits so FScc.B leaves a clean byte. */
        BWf((uint16_t)(0x7000 | ((rr & 7) << 9) | 0));
        /* Load FP{dst} = a */
        BWf(moveq_d0(a));
        BWf(0xF200); BWf(fmove_size_d0_fpn(dst, FMT_L));
        /* Load FP{src} = b */
        BWf(moveq_d0(b));
        BWf(0xF200); BWf(fmove_size_d0_fpn(src, FMT_L));
        /* FCMP FP{src},FP{dst}: ext = src<<10 | dst<<7 | opmode FCMP (0x38). */
        BWf(0xF200);
        BWf((uint16_t)(((src & 7) << 10) | ((dst & 7) << 7) | 0x38));
        /* FScc.B D{rr}: opword F240 | rr; ext = condition selector. */
        BWf((uint16_t)(0xF240 | (rr & 7)));
        BWf((uint16_t)cond);
        /* STOP #$2700 */
        BWf(0x4E72); BWf(0x2700);
        #undef BWf
        fprintf(f, "],\n");
        fprintf(f, "    \"result_reg\":%d,\n", rr);
        fprintf(f, "    \"expected\":%d\n", expected ? 0xFF : 0x00);
        fprintf(f, "  }");
    }
    return count;
}

/* FTST + FScc: unary version of FCMP+FScc. FTST FPn sets FPCC by
 * comparing FPn against zero, then FScc reads back the predicate.        */
static int gen_ftst_fscc(FILE* f, int is_first, int count) {
    static const struct { uint8_t code; const char* name; } conds[] = {
        {COND_F, "F"}, {COND_T, "T"}, {COND_EQ, "EQ"}, {COND_NE, "NE"},
        {COND_GT, "GT"}, {COND_GE, "GE"}, {COND_LT, "LT"}, {COND_LE, "LE"},
    };
    const int NC = (int)(sizeof(conds) / sizeof(conds[0]));
    for (int i = 0; i < count; ++i) {
        int8_t a = r_moveq_lim(50);
        int    src = (int)(r32() & 7);
        int    rr  = pick_result_reg();
        const int     ci = (int)(r32() % NC);
        const uint8_t cond  = conds[ci].code;
        const char*   cname = conds[ci].name;
        /* FTST FPn vs zero: compare a against 0 for predicate evaluation. */
        const int expected = eval_cond_int(cond, a, 0);

        char nm[120];
        snprintf(nm, sizeof(nm), "FTST+FS%s FP%d (%d) -> D%d #%03d",
                 cname, src, (int)a, rr, i);
        if (!(is_first && i == 0)) fprintf(f, ",\n");
        fprintf(f, "  {\n");
        fprintf(f, "    \"name\":\"%s\",\n", nm);
        fprintf(f, "    \"op_a\":%d,\n", (int)a);
        fprintf(f, "    \"program\":[");
        int first = 1;
        #define BWf(w) do { \
            if (!first) fprintf(f, ","); \
            fprintf(f, "%u,%u", ((unsigned)(w) >> 8) & 0xFF, (unsigned)(w) & 0xFF); \
            first = 0; \
        } while (0)
        BWf((uint16_t)(0x7000 | ((rr & 7) << 9) | 0));        /* MOVEQ #0,Drr */
        BWf(moveq_d0(a));
        BWf(0xF200); BWf(fmove_size_d0_fpn(src, FMT_L));      /* FMOVE.L D0,FP{src} */
        /* FTST.X FPn: ext = (src<<10) | 0x3A (opclass 000 monadic, opmode FTST). */
        BWf(0xF200);
        BWf((uint16_t)(((src & 7) << 10) | 0x3A));
        /* FScc.B D{rr} */
        BWf((uint16_t)(0xF240 | (rr & 7)));
        BWf((uint16_t)cond);
        BWf(0x4E72); BWf(0x2700);
        #undef BWf
        fprintf(f, "],\n");
        fprintf(f, "    \"result_reg\":%d,\n", rr);
        fprintf(f, "    \"expected\":%d\n", expected ? 0xFF : 0x00);
        fprintf(f, "  }");
    }
    return count;
}

/* FCMP + FBcc.W: branch on condition. If taken, marker reg keeps its
 * initial value (1); if not taken, the MOVEQ #0 between FBcc and STOP
 * runs and zeros it.                                                       */
static int gen_fcmp_fbcc(FILE* f, int is_first, int count) {
    static const struct { uint8_t code; const char* name; } conds[] = {
        {COND_F, "F"}, {COND_T, "T"}, {COND_EQ, "EQ"}, {COND_NE, "NE"},
        {COND_GT, "GT"}, {COND_GE, "GE"}, {COND_LT, "LT"}, {COND_LE, "LE"},
    };
    const int NC = (int)(sizeof(conds) / sizeof(conds[0]));
    for (int i = 0; i < count; ++i) {
        int8_t a = r_moveq_lim(50);
        int8_t b = r_moveq_lim(50);
        int    dst, src;
        pick_two_fp(&dst, &src);
        int    rr = pick_result_reg();
        const int     ci    = (int)(r32() % NC);
        const uint8_t cond  = conds[ci].code;
        const char*   cname = conds[ci].name;
        const int taken = eval_cond_int(cond, a, b);
        const int expected = taken ? 1 : 0;

        char nm[120];
        snprintf(nm, sizeof(nm), "FCMP+FB%s FP%d,FP%d (%d,%d) -> D%d #%03d",
                 cname, src, dst, (int)a, (int)b, rr, i);
        if (!(is_first && i == 0)) fprintf(f, ",\n");
        fprintf(f, "  {\n");
        fprintf(f, "    \"name\":\"%s\",\n", nm);
        fprintf(f, "    \"op_a\":%d,\"op_b\":%d,\n", (int)a, (int)b);
        fprintf(f, "    \"program\":[");
        int first = 1;
        #define BWf(w) do { \
            if (!first) fprintf(f, ","); \
            fprintf(f, "%u,%u", ((unsigned)(w) >> 8) & 0xFF, (unsigned)(w) & 0xFF); \
            first = 0; \
        } while (0)
        BWf((uint16_t)(0x7001 | ((rr & 7) << 9)));   /* MOVEQ #1,Drr (initial) */
        BWf(moveq_d0(a));
        BWf(0xF200); BWf(fmove_size_d0_fpn(dst, FMT_L));
        BWf(moveq_d0(b));
        BWf(0xF200); BWf(fmove_size_d0_fpn(src, FMT_L));
        BWf(0xF200);
        BWf((uint16_t)(((src & 7) << 10) | ((dst & 7) << 7) | 0x38));   /* FCMP */
        /* FBcc.W disp=+4 skips the 2-byte MOVEQ #0,Drr that follows. */
        BWf((uint16_t)(0xF280 | cond));
        BWf((uint16_t)0x0004);
        BWf((uint16_t)(0x7000 | ((rr & 7) << 9) | 0));   /* MOVEQ #0,Drr (skipped if branch) */
        BWf(0x4E72); BWf(0x2700);
        #undef BWf
        fprintf(f, "],\n");
        fprintf(f, "    \"result_reg\":%d,\n", rr);
        fprintf(f, "    \"expected\":%d\n", expected);
        fprintf(f, "  }");
    }
    return count;
}

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

    /* FMOVE.S variants: load via MOVE.L #ieee_single(op),D0; FMOVE.S D0,FPn.
     * Operand range still bounded so the integer round-trip works. */
    total += gen_monadic_sized(f, first, "FNEG",   OPMODE_FNEG,   fneg_compute,   FMT_S, M);
    total += gen_monadic_sized(f, first, "FABS",   OPMODE_FABS,   fabs_compute,   FMT_S, M);
    total += gen_monadic_sized(f, first, "FINT",   OPMODE_FINT,   fint_compute,   FMT_S, M);
    total += gen_dyadic_sized (f, first, "FADD",   OPMODE_FADD, fadd_compute, 127, 127, FMT_S, M);
    total += gen_dyadic_sized (f, first, "FSUB",   OPMODE_FSUB, fsub_compute, 127, 127, FMT_S, M);
    total += gen_dyadic_sized (f, first, "FMUL",   OPMODE_FMUL, fmul_compute,  10,  10, FMT_S, M);

    /* Multi-instruction tests: FDIV with arbitrary operands + FINTRZ to
     * truncate the (possibly non-integer) result, then read back as .L.
     * Verifies the FPU rounds-toward-zero correctly. */
    total += gen_fdiv_trunc (f, first, N);
    /* Same for FSQRT with arbitrary 0..127 inputs. */
    total += gen_fsqrt_trunc(f, first, N);

    /* FCMP+FScc: verifies FPCC generation and conditional-byte writeback. */
    total += gen_fcmp_fscc  (f, first, N);
    /* FTST+FScc: unary FPCC generator. */
    total += gen_ftst_fscc  (f, first, N);
    /* FCMP+FBcc.W: branch-on-condition. */
    total += gen_fcmp_fbcc  (f, first, N);

    fprintf(f, "\n]\n");
    fclose(f);
    printf("Wrote %s (%d tests, seed=0x%08X)\n", outpath, total, g_rng);
    return 0;
}
