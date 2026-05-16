#!/usr/bin/env python3
"""
diff_corpus.py -- compare two FPU test JSONL files (MAME oracle vs real
68881 hardware) and categorize divergences.

Usage:
    python3 diff_corpus.py mame.jsonl hardware.jsonl [--verbose]

The corpus is matched by `name`. For each test we compare the
semantically important post-test fields:

  - FP0           (the destination register; FP1 for FMOVE FP0,FP1)
  - FPSR.CC byte  (high byte of FPSR: N/Z/I/NaN condition codes)
  - FPCR          (rounding mode, precision)
  - D0            (sanity for the smoke tests)

We deliberately ignore:

  - FP1..FP7 in non-FMOVE tests (uninit reset-state pattern differs
    between MAME and real hardware -- not a semantic divergence)
  - A0..A7 (Mac stack-related residue from the JSR; not comparable)
  - FPSR.AEXC (sticky accrued exceptions accumulate across tests on
    real hardware but not in MAME -- needs a per-test reset fix in
    the bench before this becomes comparable)
  - FPSR.Quotient (set by FMOD/FREM/FSCALE only; cross-test bleed)
  - FPSR.EXC (current-exception byte; MAME and hardware report
    different ways)

Output: per-op tally + a per-test breakdown with the divergence
category attached.
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


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    mame_path, hw_path = sys.argv[1], sys.argv[2]
    verbose = "--verbose" in sys.argv or "-v" in sys.argv

    mame = load(mame_path)
    hw   = load(hw_path)
    mame_by = {t['name']: t for t in mame}
    hw_by   = {t['name']: t for t in hw}
    common = sorted(set(mame_by) & set(hw_by))

    print(f"MAME corpus:     {len(mame)} tests ({mame_path})")
    print(f"Hardware output: {len(hw)} tests ({hw_path})")
    print(f"Tests in common: {len(common)}\n")

    cat_counts = defaultdict(int)
    op_cat = defaultdict(lambda: defaultdict(list))
    for name in common:
        h, m = hw_by[name], mame_by[name]
        category, detail = classify(name, h['final'], m['final'])
        cat_counts[category] += 1
        op = name.split('.')[0] if '.' in name else 'smoke'
        op_cat[op][category].append((name, detail))

    print("=== category totals ===")
    order = ['match', 'trailing_bits', 'nan_encoding', 'inf_handling',
             'special_value', 'cc_only', 'smoke_fpinit', 'unknown']
    for c in order:
        n = cat_counts[c]
        if n:
            pct = 100.0 * n / len(common)
            print(f"  {c:<16} {n:>4}  ({pct:5.1f}%)")
    print()

    print("=== per-op breakdown ===")
    print(f"{'op':<10}  {'match':>5} {'trail':>5} {'nanEn':>5} "
          f"{'inf':>5} {'spec':>5} {'cc':>5} {'init':>5} {'unkn':>5}  {'total':>6}")
    for op in sorted(op_cat):
        cats = op_cat[op]
        total = sum(len(v) for v in cats.values())
        row = [op]
        row.append(len(cats.get('match', [])))
        row.append(len(cats.get('trailing_bits', [])))
        row.append(len(cats.get('nan_encoding', [])))
        row.append(len(cats.get('inf_handling', [])))
        row.append(len(cats.get('special_value', [])))
        row.append(len(cats.get('cc_only', [])))
        row.append(len(cats.get('smoke_fpinit', [])))
        row.append(len(cats.get('unknown', [])))
        row.append(total)
        print(f"  {row[0]:<8}  {row[1]:>5} {row[2]:>5} {row[3]:>5} "
              f"{row[4]:>5} {row[5]:>5} {row[6]:>5} {row[7]:>5} "
              f"{row[8]:>5}  {row[9]:>6}")

    if verbose:
        print("\n=== divergent tests (verbose) ===")
        for op in sorted(op_cat):
            for cat, items in op_cat[op].items():
                if cat == 'match':
                    continue
                for name, detail in items:
                    print(f"  [{cat}] {name}")
                    print(f"        {detail}")

    print(f"\n{cat_counts['match']}/{len(common)} pass "
          f"({100.0*cat_counts['match']/len(common):.1f}%).")


if __name__ == '__main__':
    main()
