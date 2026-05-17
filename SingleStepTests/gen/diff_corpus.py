#!/usr/bin/env python3
"""
diff_corpus.py -- compare two FPU test JSONL files (MAME oracle vs any
other corpus: real 68881 hardware, Snow emulator, verilator FPU core)
and categorize divergences.

Usage:
    python3 diff_corpus.py BASELINE.jsonl CANDIDATE.jsonl [OPTIONS]

Options:
    --json        Emit a machine-parseable JSON summary on stdout.
                  Includes overall stats, per-category counts,
                  per-op breakdown, and every test's category +
                  detail string. Good for CI / tooling / dashboards.
    --markdown    Emit a markdown report suitable for pasting into
                  README.md or core documentation. Includes header
                  stats, the category table, and the per-op table.
    --verbose     (terminal mode only) list every divergent test
                  with its category and detail.
    (no flag)     Print the human-friendly terminal report.

Convention: BASELINE is the "right answer" corpus (usually the MAME
oracle). CANDIDATE is what you're scoring (hardware run, Snow run,
verilator run). Pass rate = candidate matches baseline.

Comparison fields:
  - FP0           (destination register; FP1 for FMOVE FP0,FP1)
  - FPSR.CC byte  (high byte of FPSR: N/Z/I/NaN condition codes)
  - FPCR          (rounding mode, precision)
  - D0            (sanity for the smoke tests)

Deliberately ignored:
  - FP1..FP7 in non-FMOVE tests (uninit reset-state pattern)
  - A0..A7 (Mac stack-related residue from the JSR)
  - FPSR.AEXC / FPSR.EXC / Quotient (sticky/cross-test noise)
"""
import json
import re
import sys
from collections import defaultdict


def load(path):
    return [json.loads(line) for line in open(path) if line.strip()]


CC_NAMES = {0x80: "N", 0x40: "Z", 0x20: "I", 0x10: "NaN"}


def cc(fpsr):
    return (fpsr >> 24) & 0xFF


def classify(name, hf, mf):
    """Return (category, detail) for a divergence, or ("match", None) if
    the test passes. Categories:
        match          -- identical on the compared fields
        trailing_bits  -- FP0 mantissa differs only in last 1-3 bytes
        nan_encoding   -- HW returns 7FFF.._FFFF.. NaN, MAME returns
                          FFFF..C000.. or similar non-canonical NaN
        inf_handling   -- HW returns clean +/- inf, MAME returns NaN or
                          finite garbage
        special_value  -- 0, +/-inf, NaN as input that MAME mis-handles
        cc_only        -- FP0 matches but condition codes differ
        smoke_fpinit   -- DBG smoke test: FP0 reset state differs (HW
                          NaN-reset, MAME zero) -- expected MAME quirk
        unknown        -- anything else
    """
    fp0_match = hf['fp'][0] == mf['fp'][0]
    cc_match  = cc(hf['fpsr']) == cc(mf['fpsr'])
    fpcr_match = (hf['fpcr'] & 0xFFFFFFFF) == (mf['fpcr'] & 0xFFFFFFFF)
    d0_match = hf['d'][0] == mf['d'][0]

    if fp0_match and cc_match and fpcr_match and d0_match:
        return ("match", None)

    if name.startswith("DBG"):
        return ("smoke_fpinit",
                f"FP0 hw={hf['fp'][0]} mame={mf['fp'][0]}")

    h_fp0, m_fp0 = hf['fp'][0], mf['fp'][0]

    # NaN encoding: both report 12 hex bytes; classify by leading 4 bytes
    # plus mantissa pattern.
    def is_canonical_nan(s):
        return s.startswith("7fff0000ffffffff") or s.startswith("ffff0000ffffffff")
    def is_mame_nan(s):
        return s.startswith("7fff0000c0000000") or s.startswith("ffff0000c0000000")

    if is_canonical_nan(h_fp0) and is_mame_nan(m_fp0):
        return ("nan_encoding",
                f"hw=canonical NaN, mame=non-canonical NaN; "
                f"FP0 hw={h_fp0} mame={m_fp0}")
    if is_mame_nan(h_fp0) and is_canonical_nan(m_fp0):
        return ("nan_encoding",
                f"hw=non-canonical NaN, mame=canonical NaN; "
                f"FP0 hw={h_fp0} mame={m_fp0}")

    # Trailing-bit precision: same exp+sign+upper mantissa, differ in
    # final 1-3 bytes.
    if not fp0_match and h_fp0[:20] == m_fp0[:20]:
        return ("trailing_bits",
                f"differ in last bytes; hw=...{h_fp0[-8:]} mame=...{m_fp0[-8:]}")

    # +/- infinity in HW, finite or weird in MAME (or vice versa)
    def is_inf(s):
        return s in ("7fff00000000000000000000", "ffff00000000000000000000",
                     "7fff00008000000000000000", "ffff00008000000000000000")
    if is_inf(h_fp0) and not is_inf(m_fp0):
        return ("inf_handling",
                f"hw=inf, mame=non-inf; FP0 mame={m_fp0}")
    if is_inf(m_fp0) and not is_inf(h_fp0):
        return ("inf_handling",
                f"mame=inf, hw=non-inf; FP0 hw={h_fp0}")

    # Operand involved a special value -- categorize by name
    if re.search(r'(neg_inf|pos_inf|qnan|neg_zero)', name):
        return ("special_value",
                f"FP0 hw={h_fp0} mame={m_fp0} "
                f"CC hw={cc(hf['fpsr']):02x} mame={cc(mf['fpsr']):02x}")

    if fp0_match and not cc_match:
        return ("cc_only",
                f"CC hw={cc(hf['fpsr']):02x} mame={cc(mf['fpsr']):02x}")

    return ("unknown",
            f"FP0 hw={h_fp0} mame={m_fp0} "
            f"CC hw={cc(hf['fpsr']):02x} mame={cc(mf['fpsr']):02x}")


CATEGORY_ORDER = ['match', 'trailing_bits', 'nan_encoding',
                  'inf_handling', 'special_value', 'cc_only',
                  'smoke_fpinit', 'unknown']

CATEGORY_HELP = {
    'match':         "candidate matches baseline byte-for-byte",
    'trailing_bits': "FP0 differs only in the last 1-3 mantissa bytes",
    'nan_encoding':  "different NaN bit pattern",
    'inf_handling':  "one side returns inf, the other doesn't",
    'special_value': "operand was inf/NaN/-0 and results disagree",
    'cc_only':       "FP0 matches but FPSR.CC byte differs",
    'smoke_fpinit':  "reset-state FP register pattern differs (a known MAME bug)",
    'unknown':       "uncategorized divergence",
}


def build_report(baseline_path, candidate_path):
    """Run the comparison and return a structured dict with all the
    data the renderers need. Renderer functions consume this dict."""
    baseline  = load(baseline_path)
    candidate = load(candidate_path)
    base_by = {t['name']: t for t in baseline}
    cand_by = {t['name']: t for t in candidate}
    common = sorted(set(base_by) & set(cand_by))

    cat_counts = defaultdict(int)
    op_cat = defaultdict(lambda: defaultdict(list))
    test_rows = []
    for name in common:
        b, c = base_by[name], cand_by[name]
        category, detail = classify(name, c['final'], b['final'])
        cat_counts[category] += 1
        op = name.split('.')[0] if '.' in name else 'smoke'
        op_cat[op][category].append((name, detail))
        test_rows.append({"name": name, "op": op,
                          "category": category, "detail": detail})

    per_op = {}
    for op, cats in op_cat.items():
        total = sum(len(v) for v in cats.values())
        per_op[op] = {
            "total": total,
            **{cat: len(cats.get(cat, [])) for cat in CATEGORY_ORDER},
            "pass_rate": (len(cats.get('match', [])) / total) if total else 0,
        }

    return {
        "baseline_path":  baseline_path,
        "candidate_path": candidate_path,
        "baseline_count":  len(baseline),
        "candidate_count": len(candidate),
        "common_count": len(common),
        "match_count":  cat_counts['match'],
        "pass_rate": (cat_counts['match'] / len(common)) if common else 0,
        "categories": {c: cat_counts[c] for c in CATEGORY_ORDER},
        "per_op": per_op,
        "tests": test_rows,
    }


def render_terminal(rep, verbose=False):
    print(f"Baseline ({rep['baseline_path']}):  {rep['baseline_count']} tests")
    print(f"Candidate ({rep['candidate_path']}): {rep['candidate_count']} tests")
    print(f"Tests in common: {rep['common_count']}\n")
    print("=== category totals ===")
    for c in CATEGORY_ORDER:
        n = rep['categories'].get(c, 0)
        if n:
            pct = 100.0 * n / rep['common_count']
            print(f"  {c:<16} {n:>4}  ({pct:5.1f}%)")
    print("\n=== per-op breakdown ===")
    print(f"{'op':<10}  {'match':>5} {'trail':>5} {'nanEn':>5} "
          f"{'inf':>5} {'spec':>5} {'cc':>5} {'init':>5} {'unkn':>5}  {'total':>6}")
    for op in sorted(rep['per_op']):
        d = rep['per_op'][op]
        print(f"  {op:<8}  {d['match']:>5} {d['trailing_bits']:>5} "
              f"{d['nan_encoding']:>5} {d['inf_handling']:>5} "
              f"{d['special_value']:>5} {d['cc_only']:>5} "
              f"{d['smoke_fpinit']:>5} {d['unknown']:>5}  {d['total']:>6}")
    if verbose:
        print("\n=== divergent tests ===")
        for t in rep['tests']:
            if t['category'] != 'match':
                print(f"  [{t['category']}] {t['name']}")
                print(f"        {t['detail']}")
    print(f"\n{rep['match_count']}/{rep['common_count']} pass "
          f"({100.0 * rep['pass_rate']:.1f}%).")


def render_json(rep):
    print(json.dumps(rep, indent=2))


def render_markdown(rep):
    """Drop-in markdown for documentation."""
    print(f"# FPU corpus comparison")
    print()
    print(f"- **Baseline:** `{rep['baseline_path']}` ({rep['baseline_count']} tests)")
    print(f"- **Candidate:** `{rep['candidate_path']}` ({rep['candidate_count']} tests)")
    print(f"- **Tests compared:** {rep['common_count']}")
    print(f"- **Pass rate:** **{rep['match_count']} / {rep['common_count']} "
          f"({100.0 * rep['pass_rate']:.1f}%)**")
    print()
    print("## Category totals")
    print()
    print("| Category | Count | % | Meaning |")
    print("|---|---:|---:|---|")
    for c in CATEGORY_ORDER:
        n = rep['categories'].get(c, 0)
        if n:
            pct = 100.0 * n / rep['common_count']
            print(f"| `{c}` | {n} | {pct:.1f}% | {CATEGORY_HELP[c]} |")
    print()
    print("## Per-op breakdown")
    print()
    print("| op | total | match | trail | nanEnc | inf | spec | cc | init | unkn | pass% |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for op in sorted(rep['per_op']):
        d = rep['per_op'][op]
        pct = 100.0 * d['pass_rate']
        print(f"| `{op}` | {d['total']} | {d['match']} | {d['trailing_bits']} | "
              f"{d['nan_encoding']} | {d['inf_handling']} | "
              f"{d['special_value']} | {d['cc_only']} | "
              f"{d['smoke_fpinit']} | {d['unknown']} | {pct:.0f}% |")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    flags = [a for a in sys.argv[1:] if a.startswith('-')]
    if len(args) < 2:
        print(__doc__)
        sys.exit(1)
    baseline_path, candidate_path = args[0], args[1]
    rep = build_report(baseline_path, candidate_path)

    if '--json' in flags:
        render_json(rep)
    elif '--markdown' in flags or '--md' in flags:
        render_markdown(rep)
    else:
        render_terminal(rep, verbose=('--verbose' in flags or '-v' in flags))


if __name__ == '__main__':
    main()
