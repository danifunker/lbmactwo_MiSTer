/*
 * Test corpus generator — uses Musashi as the reference oracle.
 *
 * For each opcode in a configurable list, generates N random test cases:
 *   1. Randomize CPU registers and a small operand RAM window.
 *   2. Place the encoded instruction at a fixed PC.
 *   3. Run Musashi for one instruction.
 *   4. Emit pre/post state as JSON (state-only schema; see SCHEMA.md).
 *
 * Usage: gen <out_dir> [seed]
 *
 * First slice: ADD.l Dx,Dy only. Builds out from there once the bench can
 * consume the format.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <inttypes.h>

#include "m68k.h"

/* ---------- 16 MiB flat RAM backing Musashi -------------------------- */
#define RAM_BYTES (1u << 24)
static uint8_t g_ram[RAM_BYTES];

static inline uint8_t  rd8(unsigned a)  { return g_ram[a & (RAM_BYTES - 1)]; }
static inline uint16_t rd16(unsigned a) {
    a &= (RAM_BYTES - 1);
    return ((uint16_t)g_ram[a] << 8) | g_ram[(a + 1) & (RAM_BYTES - 1)];
}
static inline uint32_t rd32(unsigned a) {
    return ((uint32_t)rd16(a) << 16) | rd16(a + 2);
}
static inline void wr8(unsigned a, uint8_t v)  { g_ram[a & (RAM_BYTES - 1)] = v; }
static inline void wr16(unsigned a, uint16_t v) {
    wr8(a, v >> 8); wr8(a + 1, v & 0xFF);
}
static inline void wr32(unsigned a, uint32_t v) {
    wr16(a, v >> 16); wr16(a + 2, v & 0xFFFF);
}

/* Musashi memory callbacks -------------------------------------------
 *
 * When the bench is generating "run one instruction" snapshots we want
 * to stop the CPU the moment fetching crosses past the test instruction
 * boundary. g_stop_below_pc is set to the address of the byte JUST AFTER
 * the test instruction. Any immediate fetch at >= that address ends the
 * timeslice. */
static uint32_t g_stop_below_pc = 0xFFFFFFFFu;
extern void m68k_end_timeslice(void);

unsigned int m68k_read_memory_8 (unsigned int a)  { return rd8(a); }
unsigned int m68k_read_memory_16(unsigned int a)  {
    if (a >= g_stop_below_pc) m68k_end_timeslice();
    return rd16(a);
}
unsigned int m68k_read_memory_32(unsigned int a)  {
    if (a >= g_stop_below_pc) m68k_end_timeslice();
    return rd32(a);
}
unsigned int m68k_read_immediate_8 (unsigned int a) {
    if (a >= g_stop_below_pc) m68k_end_timeslice();
    return rd8(a);
}
unsigned int m68k_read_immediate_16(unsigned int a) {
    if (a >= g_stop_below_pc) m68k_end_timeslice();
    return rd16(a);
}
unsigned int m68k_read_immediate_32(unsigned int a) {
    if (a >= g_stop_below_pc) m68k_end_timeslice();
    return rd32(a);
}
unsigned int m68k_read_pcrelative_8 (unsigned int a) { return rd8(a); }
unsigned int m68k_read_pcrelative_16(unsigned int a) { return rd16(a); }
unsigned int m68k_read_pcrelative_32(unsigned int a) { return rd32(a); }
unsigned int m68k_read_disassembler_8 (unsigned int a) { return rd8(a); }
unsigned int m68k_read_disassembler_16(unsigned int a) { return rd16(a); }
unsigned int m68k_read_disassembler_32(unsigned int a) { return rd32(a); }
void m68k_write_memory_8 (unsigned int a, unsigned int v) { wr8(a, v); }
void m68k_write_memory_16(unsigned int a, unsigned int v) { wr16(a, v); }
void m68k_write_memory_32(unsigned int a, unsigned int v) { wr32(a, v); }

/* ---------- Tiny seeded RNG (xorshift32) ----------------------------- */
static uint32_t g_rng = 0xC0FFEE01;
static uint32_t r32(void) {
    uint32_t x = g_rng;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    return g_rng = x;
}

/* ---------- Test-state snapshot ------------------------------------- */
typedef struct {
    uint32_t d[8], a[8];
    uint32_t pc, sr, usp, ssp, vbr;
} cpu_state_t;

static void snap(cpu_state_t* s) {
    for (int i = 0; i < 8; ++i) s->d[i] = m68k_get_reg(NULL, M68K_REG_D0 + i);
    for (int i = 0; i < 8; ++i) s->a[i] = m68k_get_reg(NULL, M68K_REG_A0 + i);
    s->pc  = m68k_get_reg(NULL, M68K_REG_PC);
    s->sr  = m68k_get_reg(NULL, M68K_REG_SR);
    s->usp = m68k_get_reg(NULL, M68K_REG_USP);
    s->ssp = m68k_get_reg(NULL, M68K_REG_ISP);
    s->vbr = m68k_get_reg(NULL, M68K_REG_VBR);
}

/* ---------- JSON emission ------------------------------------------- */
static void emit_regs(FILE* f, const cpu_state_t* s, const char* indent) {
    fprintf(f, "%s\"d0\":%u,\"d1\":%u,\"d2\":%u,\"d3\":%u,",
            indent, s->d[0], s->d[1], s->d[2], s->d[3]);
    fprintf(f, "\"d4\":%u,\"d5\":%u,\"d6\":%u,\"d7\":%u,\n",
            s->d[4], s->d[5], s->d[6], s->d[7]);
    fprintf(f, "%s\"a0\":%u,\"a1\":%u,\"a2\":%u,\"a3\":%u,",
            indent, s->a[0], s->a[1], s->a[2], s->a[3]);
    fprintf(f, "\"a4\":%u,\"a5\":%u,\"a6\":%u,\"a7\":%u,\n",
            s->a[4], s->a[5], s->a[6], s->a[7]);
    fprintf(f, "%s\"pc\":%u,\"sr\":%u,\"usp\":%u,\"ssp\":%u,\"vbr\":%u",
            indent, s->pc, s->sr, s->usp, s->ssp, s->vbr);
}

/* Emit ram_pre as an array of [addr,byte] for every nonzero byte in the
 * operand window. ram_post emits ONLY bytes that differ from ram_pre. */
typedef struct { uint32_t lo, hi; } window_t;

static void emit_ram_initial(FILE* f, const window_t* w) {
    fprintf(f, "[");
    int first = 1;
    for (uint32_t a = w->lo; a < w->hi; ++a) {
        if (g_ram[a] == 0) continue;
        fprintf(f, "%s[%u,%u]", first ? "" : ",", a, g_ram[a]);
        first = 0;
    }
    fprintf(f, "]");
}

static void emit_ram_diff(FILE* f, const window_t* w,
                          const uint8_t* pre, const uint8_t* post) {
    fprintf(f, "[");
    int first = 1;
    for (uint32_t a = w->lo; a < w->hi; ++a) {
        if (pre[a] == post[a]) continue;
        fprintf(f, "%s[%u,%u]", first ? "" : ",", a, post[a]);
        first = 0;
    }
    fprintf(f, "]");
}

/* ---------- Generic single-instruction test harness ------------------ */
/* All current generators emit a single 16-bit opcode at PC and stop the
 * CPU at PC+2. If we add multi-word ops later (immediates, displacements),
 * the harness needs an `instr_len` parameter; for now it's hardcoded. */
#define TEST_PC  0x1000u
static const window_t g_win = { TEST_PC, TEST_PC + 16 };

/* Random src/dst register pair. dst_eq_src=1 forces overlap (some
 * encodings care, e.g. CMP D0,D0). */
static void pick_dn_pair(int* dst, int* src) {
    *src = r32() & 7;
    *dst = r32() & 7;
}

/* Run one test: install opcode at TEST_PC, set up regs, snap pre, run one
 * instruction, snap post, emit JSON. Caller passes the emitter the name. */
typedef void (*op_encoder_t)(uint16_t* op, int dst, int src, int imm);

static void emit_one_test(FILE* f, int is_first, const char* name,
                          uint16_t op) {
    memset(g_ram, 0, RAM_BYTES);
    wr32(0, 0x00FFFFF8);   /* SSP */
    wr32(4, TEST_PC);      /* PC after reset */
    wr16(TEST_PC, op);
    wr16(TEST_PC + 2, 0x4E71);  /* NOP landing pad */
    m68k_pulse_reset();

    for (int r = 0; r < 8; ++r) {
        m68k_set_reg(M68K_REG_D0 + r, r32());
        if (r < 7) m68k_set_reg(M68K_REG_A0 + r, r32() & 0x00FFFFFE);
    }
    m68k_set_reg(M68K_REG_SR, 0x2000);  /* supervisor, no T/I */

    static uint8_t ram_pre[RAM_BYTES];
    cpu_state_t pre;
    snap(&pre);
    memcpy(ram_pre, g_ram, RAM_BYTES);

    g_stop_below_pc = TEST_PC + 2;
    (void)m68k_execute(100);
    g_stop_below_pc = 0xFFFFFFFFu;

    cpu_state_t post;
    snap(&post);
    post.pc = TEST_PC + 2;  /* architectural post-instruction PC */

    if (!is_first) fprintf(f, ",\n");
    fprintf(f, "  {\n");
    fprintf(f, "    \"name\":\"%s\",\n", name);
    fprintf(f, "    \"initial\":{\n");
    emit_regs(f, &pre, "      ");
    fprintf(f, ",\n      \"ram\":");
    emit_ram_initial(f, &g_win);
    fprintf(f, "\n    },\n");
    fprintf(f, "    \"final\":{\n");
    emit_regs(f, &post, "      ");
    fprintf(f, ",\n      \"ram\":");
    emit_ram_diff(f, &g_win, ram_pre, g_ram);
    fprintf(f, "\n    }\n");
    fprintf(f, "  }");
}

/* ---------- Opcode encoders (single-word, Dn-only operands) --------- */
/* Standard ALU op format: nnnn ddd ooo sss mmm rrr
 * For Dn,Dn dst (opmode 1xx, .L = 110): base | (dst<<9) | size_bits | src.
 * Sizes for "Dn,<ea>" direction (op modifies <ea>):
 *   .B = 0x100, .W = 0x140, .L = 0x180 — but we use the reverse:
 * For "<ea>,Dn" direction (op modifies Dn):
 *   .B = 0x000, .W = 0x040, .L = 0x080 — src is in mode 000, reg = sss. */
#define ENC_DnDn(base, dst, src, sizeb) \
    ((uint16_t)((base) | ((dst) & 7) << 9 | (sizeb) | ((src) & 7)))

/* base patterns (bits 15-12) for arithmetic/logic into Dn:
 *   ADD = 0xD000, SUB = 0x9000, AND = 0xC000, OR = 0x8000,
 *   EOR uses different encoding (only Dn,<ea>); CMP = 0xB000. */
typedef struct {
    const char* name;     /* e.g. "ADD" */
    uint16_t    base;     /* e.g. 0xD000 */
    int         has_l, has_w, has_b;
} alu_op_t;

static const alu_op_t g_alu_ops[] = {
    { "ADD", 0xD000, 1, 1, 1 },
    { "SUB", 0x9000, 1, 1, 1 },
    { "AND", 0xC000, 1, 1, 1 },
    { "OR",  0x8000, 1, 1, 1 },
    { "CMP", 0xB000, 1, 1, 1 },
};
#define N_ALU_OPS (sizeof(g_alu_ops) / sizeof(g_alu_ops[0]))

/* EOR.L Dx,Dy uses the "Dn,<ea>" direction: 1011 sss 1 10 000 ddd =
 * 0xB180 | (src<<9) | dst. (EOR only has the Dn,<ea> form.) */
static uint16_t encode_eor_l(int dst, int src) {
    return (uint16_t)(0xB180 | ((src & 7) << 9) | (dst & 7));
}

/* Unary ops on Dn (.L). Encoding base | dst, with .L = 0x80 added. */
typedef struct { const char* name; uint16_t base; } unary_op_t;
static const unary_op_t g_unary_ops[] = {
    { "NEG", 0x4480 },   /* NEG.L  Dn = 0x4480 | dn */
    { "NOT", 0x4680 },   /* NOT.L  Dn = 0x4680 | dn */
    { "CLR", 0x4280 },   /* CLR.L  Dn = 0x4280 | dn */
    { "TST", 0x4A80 },   /* TST.L  Dn = 0x4A80 | dn */
};
#define N_UNARY_OPS (sizeof(g_unary_ops) / sizeof(g_unary_ops[0]))

/* Shift/rotate ops on Dn (.L, immediate count #1..#7).
 * Encoding: 1110 ccc d ss i tt rrr where
 *   ccc=count (1..7, 0 means 8), d=direction (0=right, 1=left),
 *   ss=size (10=.L), i=0 for immediate, tt=type (00=AS,01=LS,10=ROX,11=RO),
 *   rrr=Dn target.
 * Convenience base: 0xE000 | (count<<9) | (dir<<8) | 0x80 | (type<<3) | dn */
typedef struct { const char* name; int type; int dir; } shift_op_t;
static const shift_op_t g_shift_ops[] = {
    { "ASR",  0, 0 }, { "ASL",  0, 1 },
    { "LSR",  1, 0 }, { "LSL",  1, 1 },
    { "ROXR", 2, 0 }, { "ROXL", 2, 1 },
    { "ROR",  3, 0 }, { "ROL",  3, 1 },
};
#define N_SHIFT_OPS (sizeof(g_shift_ops) / sizeof(g_shift_ops[0]))

/* ---------- Per-family generators ----------------------------------- */
static void gen_alu_l(FILE* f, const alu_op_t* op, int count) {
    fprintf(f, "[\n");
    for (int i = 0; i < count; ++i) {
        int src, dst; pick_dn_pair(&dst, &src);
        uint16_t opc = ENC_DnDn(op->base, dst, src, 0x080);
        char name[64];
        snprintf(name, sizeof(name), "%s.l D%d,D%d #%05d",
                 op->name, src, dst, i);
        emit_one_test(f, i == 0, name, opc);
    }
    fprintf(f, "\n]\n");
}

static void gen_eor_l(FILE* f, int count) {
    fprintf(f, "[\n");
    for (int i = 0; i < count; ++i) {
        int src, dst; pick_dn_pair(&dst, &src);
        uint16_t opc = encode_eor_l(dst, src);
        char name[64];
        snprintf(name, sizeof(name), "EOR.l D%d,D%d #%05d", src, dst, i);
        emit_one_test(f, i == 0, name, opc);
    }
    fprintf(f, "\n]\n");
}

static void gen_unary_l(FILE* f, const unary_op_t* op, int count) {
    fprintf(f, "[\n");
    for (int i = 0; i < count; ++i) {
        int dst = r32() & 7;
        uint16_t opc = (uint16_t)(op->base | dst);
        char name[64];
        snprintf(name, sizeof(name), "%s.l D%d #%05d", op->name, dst, i);
        emit_one_test(f, i == 0, name, opc);
    }
    fprintf(f, "\n]\n");
}

static void gen_shift_l(FILE* f, const shift_op_t* op, int count) {
    fprintf(f, "[\n");
    for (int i = 0; i < count; ++i) {
        int dst = r32() & 7;
        int cnt = (r32() % 7) + 1;  /* 1..7; avoid 0 (=8) for now */
        uint16_t opc = (uint16_t)(0xE000 | (cnt << 9) | (op->dir << 8)
                                  | 0x80 | (op->type << 3) | dst);
        char name[64];
        snprintf(name, sizeof(name), "%s.l #%d,D%d #%05d",
                 op->name, cnt, dst, i);
        emit_one_test(f, i == 0, name, opc);
    }
    fprintf(f, "\n]\n");
}

/* ---------------------------------------------------------------------- */
int main(int argc, char** argv) {
    const char* outdir = (argc > 1) ? argv[1] : ".";
    if (argc > 2) g_rng = (uint32_t)strtoul(argv[2], NULL, 0);

    m68k_init();
    m68k_set_cpu_type(M68K_CPU_TYPE_68020);
    m68k_pulse_reset();

    char path[512];
    FILE* f;
    const int PER_FAMILY = 20;
    int total = 0, files = 0;

#define OPEN(fmt, ...) do { \
    snprintf(path, sizeof(path), "%s/" fmt, outdir, ##__VA_ARGS__); \
    f = fopen(path, "w"); \
    if (!f) { perror(path); return 1; } \
} while (0)
#define CLOSE(n)  do { fclose(f); total += (n); ++files; } while (0)

    for (unsigned i = 0; i < N_ALU_OPS; ++i) {
        OPEN("%s.l.json", g_alu_ops[i].name);
        gen_alu_l(f, &g_alu_ops[i], PER_FAMILY);
        CLOSE(PER_FAMILY);
    }
    OPEN("EOR.l.json");
    gen_eor_l(f, PER_FAMILY);
    CLOSE(PER_FAMILY);

    for (unsigned i = 0; i < N_UNARY_OPS; ++i) {
        OPEN("%s.l.json", g_unary_ops[i].name);
        gen_unary_l(f, &g_unary_ops[i], PER_FAMILY);
        CLOSE(PER_FAMILY);
    }

    for (unsigned i = 0; i < N_SHIFT_OPS; ++i) {
        OPEN("%s.l.json", g_shift_ops[i].name);
        gen_shift_l(f, &g_shift_ops[i], PER_FAMILY);
        CLOSE(PER_FAMILY);
    }

    printf("Wrote %d tests across %d files in %s/ (seed=0x%08X)\n",
           total, files, outdir, g_rng);
    return 0;
}
