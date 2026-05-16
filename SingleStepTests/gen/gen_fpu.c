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
 * For monadic ops (FNEG/FABS/FINT/FINTRZ), src=dst=0.
 * For dyadic ops with FP1 as second operand, src=001 (FP1) into dst=000 (FP0).
 */
#define OPMODE_FADD   0x22
#define OPMODE_FSUB   0x28
#define OPMODE_FMUL   0x23
#define OPMODE_FNEG   0x1A
#define OPMODE_FABS   0x18
#define OPMODE_FINT   0x01
#define OPMODE_FINTRZ 0x03

static uint16_t ext_monadic(uint8_t opmode) {
    /* src=FP0 (000), dst=FP0 (000), opmode */
    return (uint16_t)opmode;
}
static uint16_t ext_dyadic_fp1_fp0(uint8_t opmode) {
    /* src=FP1 (001<<10 = 0x400), dst=FP0 (000<<7), opmode */
    return (uint16_t)(0x0400 | opmode);
}

/* MOVEQ #imm,D0: opcode 0x7000 | (D0<<9) | imm = 0x7000 | imm (D0=0). */
static uint16_t moveq_d0(int8_t imm) { return (uint16_t)(0x7000 | (uint8_t)imm); }
/* FMOVE.L D0,FPn: opword $F200 | EA(D0=0) = $F200; ext = opclass 010 (EA→FPn),
 * fmt=L (000<<10), dst FPn (n<<7), opmode FMOVE (0x00). */
static uint16_t fmove_l_d0_fpn(int n) { return (uint16_t)(0x4000 | ((n & 7) << 7)); }
/* FMOVE.L FP0,Dn: opword $F200 | n (EA mode 0 reg n); ext = opclass 011 (FPn→EA),
 * dst fmt L (000<<10), src FP0 (000<<7), k=0. */
static uint16_t fmove_l_fp0_dn_opw(int n) { return (uint16_t)(0xF200 | (n & 7)); }

/* ---------- JSON emission ------------------------------------------- */
typedef struct {
    const char* name;
    int   has_b;         /* 1 = dyadic (load FP1 from op_b too) */
    int   op_a;          /* op_a value (int8) */
    int   op_b;          /* op_b value (int8) — only if has_b */
    uint16_t test_op;    /* test instruction opword */
    uint16_t test_ext;   /* test instruction ext word */
    int   result_reg;    /* Dn that receives FMOVE.L FP0,Dn */
    int32_t expected;    /* expected value of D{result_reg} */
} test_t;

static void emit_program(FILE* f, const test_t* t) {
    /* Build the program byte sequence inline as a JSON array. */
    fprintf(f, "[");
    int first = 1;
    #define BW(w) do { \
        if (!first) fprintf(f, ","); \
        fprintf(f, "%u,%u", ((unsigned)(w) >> 8) & 0xFF, (unsigned)(w) & 0xFF); \
        first = 0; \
    } while (0)

    BW(moveq_d0((int8_t)t->op_a));
    BW(0xF200);                     /* FMOVE.L D0,FP0 opword */
    BW(fmove_l_d0_fpn(0));          /* ext 0x4000 */
    if (t->has_b) {
        BW(moveq_d0((int8_t)t->op_b));
        BW(0xF200);                 /* FMOVE.L D0,FP1 opword */
        BW(fmove_l_d0_fpn(1));      /* ext 0x4080 */
    }
    BW(t->test_op);                 /* test instruction */
    BW(t->test_ext);
    BW(fmove_l_fp0_dn_opw(t->result_reg));  /* FMOVE.L FP0,D{rr} opword */
    BW(0x6000);                     /* ext for FMOVE.L FP0→EA */
    BW(0x4E72);                     /* STOP #$2700 */
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

/* ---------- Per-op generators --------------------------------------- */
static int gen_monadic(FILE* f, int is_first, const char* op_name,
                       uint8_t opmode, int (*compute)(int), int count) {
    for (int i = 0; i < count; ++i) {
        int8_t a = r_moveq();
        test_t t = {
            .name = NULL, .has_b = 0, .op_a = a, .op_b = 0,
            .test_op = 0xF200, .test_ext = ext_monadic(opmode),
            .result_reg = 1, .expected = compute(a),
        };
        char nm[64];
        snprintf(nm, sizeof(nm), "%s #%d #%03d", op_name, a, i);
        t.name = nm;
        emit_test_clean(f, is_first && i == 0, &t);
    }
    return count;
}

static int gen_dyadic(FILE* f, int is_first, const char* op_name,
                      uint8_t opmode, int (*compute)(int, int),
                      int limit_a, int limit_b, int count) {
    for (int i = 0; i < count; ++i) {
        int8_t a = r_moveq_lim(limit_a);
        int8_t b = r_moveq_lim(limit_b);
        test_t t = {
            .name = NULL, .has_b = 1, .op_a = a, .op_b = b,
            .test_op = 0xF200, .test_ext = ext_dyadic_fp1_fp0(opmode),
            .result_reg = 2, .expected = compute(a, b),
        };
        char nm[64];
        snprintf(nm, sizeof(nm), "%s FP1,FP0 (%d,%d) #%03d", op_name, a, b, i);
        t.name = nm;
        emit_test_clean(f, is_first && i == 0, &t);
    }
    return count;
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
    const int N = 20;

    total += gen_monadic(f, first, "FNEG.X",   OPMODE_FNEG,   fneg_compute,   N); first = 0;
    total += gen_monadic(f, first, "FABS.X",   OPMODE_FABS,   fabs_compute,   N);
    total += gen_monadic(f, first, "FINT.X",   OPMODE_FINT,   fint_compute,   N);
    total += gen_monadic(f, first, "FINTRZ.X", OPMODE_FINTRZ, fintrz_compute, N);
    /* Dyadic with bounded operands so int32 result is safe.
     * FADD/FSUB: ±127 each, sum ±254 — fits easily.
     * FMUL: ±10 each, product ±100. */
    total += gen_dyadic (f, first, "FADD",     OPMODE_FADD, fadd_compute, 127, 127, N);
    total += gen_dyadic (f, first, "FSUB",     OPMODE_FSUB, fsub_compute, 127, 127, N);
    total += gen_dyadic (f, first, "FMUL",     OPMODE_FMUL, fmul_compute,  10,  10, N);

    fprintf(f, "\n]\n");
    fclose(f);
    printf("Wrote %s (%d tests, seed=0x%08X)\n", outpath, total, g_rng);
    return 0;
}
