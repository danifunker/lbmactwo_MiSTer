#!/usr/bin/env python3
"""Offline regression gate for the OSD "Original" aspect ratio (LBMacTwo.sv).

Why this exists: the Verilator sim does NOT instantiate video_freak
(verilator/sim.v is the sim top; grep confirms no video_freak/VIDEO_ARX), so
the scaler request path has no simulation coverage. This script is a faithful
python model of sys/video_freak.sv :: video_scale_int (the cnt-FSM, floor
integer division exactly like sys_udiv) and asserts the properties the 4:3
fix must hold. Run it after ANY change to the video_freak ARX/ARY wiring:

    python3 scripts/aspect_check.py     (exit 0 = pass, non-zero = fail)

History: "Original" shipped as 256:171 (the Mac Plus 512x342 screen,
inherited at the initial import). Both MDC824 monitor modes are 4:3
(640x480 and 512x384), so 256:171 (1.497:1) squished the picture ~12% and —
worse — OVERFLOWED the integer scaler on 5:4/4:3 panels: htarget =
oheight*ARX/ARY asked 1437px of a 1280x1024 panel (VGA mode, V-Integer) and
1149px of a 1024x768 panel (12" mode) -> the scaler requested a wider-than-
panel image -> blank screen. LBMacTwo.sv now requests 12'd4 : 12'd3.
This script proves the fix and CONTAINS A CANARY: it also asserts the OLD
256:171 values still trip the overflow detector, so a future edit that
weakens the model cannot silently pass.
"""
import sys

FAIL = []


def scale_int(W, H, SCALE, hsize, vsize, arx, ary):
    """Model of sys/video_freak.sv::video_scale_int.

    Returns ('ratio', arx, ary) when the module passes the aspect through
    (SCALE off, or integer scaling impossible), else ('size', width, height)
    mirroring the {1'b1, size} outputs. All divisions are floor (sys_udiv).
    SCALE encoding per LBMacTwo CONF_STR "OBC": 0=Normal(off), 1=V-Integer,
    2=Narrower HV-Integer, 3=Wider HV-Integer.
    """
    if SCALE == 0 or (ary == 0 and arx != 0):
        return ('ratio', arx, ary)

    k = H // vsize                                  # cnt0/1
    if k == 0:                                      # panel shorter than source
        return ('ratio', arx, ary)
    oheight = vsize * k                             # cnt1/2

    htarget = None
    if ary == 0:                                    # cnt2 -> width path (cnt8..11)
        div_num = W
        kw = W // hsize
        kw = kw if kw else 1
        hinteger = hsize * kw
        oheight = vsize * kw
    else:
        htarget = (oheight * arx) // ary            # cnt3/4
        div_num = htarget                           # cnt5 loads div_num <= htarget
        kw = htarget // hsize                       # cnt5 (floor; the "ceiling"
        kw = kw if kw else 1                        #  comment in the RTL is stale)
        cand = hsize * kw                           # cnt6
        if cand <= W:                               # cnt7 take it
            hinteger = cand
        else:                                       # cnt7 fails -> clamp path 8..11
            div_num = W
            kw = W // hsize
            kw = kw if kw else 1
            hinteger = hsize * kw
            oheight = vsize * kw

    wideres = hinteger + hsize                      # cnt12
    wres = hinteger if (htarget is not None and hinteger == htarget) else wideres

    if SCALE == 2:                                  # Narrower HV-Integer
        aw = hinteger
    elif SCALE == 3:                                # Wider HV-Integer
        aw = hinteger if wres > W else wres
    else:                                           # SCALE==1 V-Integer: div_num
        aw = div_num                                #  (= htarget, or W after clamp)
    return ('size', aw, oheight)


def check(cond, msg):
    if not cond:
        FAIL.append(msg)
        print("FAIL:", msg)


PANELS = [(1280, 720), (1920, 1080), (1280, 1024), (1024, 768),
          (2560, 1440), (800, 600)]
SOURCES = [(640, 480), (512, 384)]                 # 13" VGA mode, 12" RGB mode
MODES = {1: "V-Integer", 2: "Narrower", 3: "Wider"}

# ---- Property tests for the fixed 4:3 request --------------------------------
for (W, H) in PANELS:
    for (hs, vs) in SOURCES:
        for sc in MODES:
            kind, w, h = scale_int(W, H, sc, hs, vs, 4, 3)
            where = f"{W}x{H} {MODES[sc]} src {hs}x{vs}"
            if kind == 'ratio':
                # integer scaling impossible -> module passes 4:3 through;
                # the ratio path cannot overflow. Nothing more to assert.
                continue
            check(w <= W, f"{where}: requested width {w} > panel {W}")
            check(h <= H, f"{where}: requested height {h} > panel {H}")
            check(w * 3 == h * 4, f"{where}: {w}x{h} is not exactly 4:3")
            check(w % hs == 0, f"{where}: width {w} not a multiple of {hs}")
            check(h % vs == 0, f"{where}: height {h} not a multiple of {vs}")

# ---- Spot-check table (VGA 640x480 source), from the fix writeup -------------
EXPECT = {
    (1280, 720):  (640, 480),
    (1920, 1080): (1280, 960),
    (1280, 1024): (1280, 960),
    (2560, 1440): (1920, 1440),
}
for (W, H), (ew, eh) in EXPECT.items():
    for sc in MODES:
        kind, w, h = scale_int(W, H, sc, 640, 480, 4, 3)
        check((kind, w, h) == ('size', ew, eh),
              f"{W}x{H} {MODES[sc]}: got {kind} {w}x{h}, expected {ew}x{eh}")

# ---- Canary: the OLD 256:171 request must still trip the detector ------------
# (proves the model keeps its sensitivity; both were real blank-screen reports)
kind, w, h = scale_int(1280, 1024, 1, 640, 480, 256, 171)
check(kind == 'size' and w == 1437 and w > 1280,
      f"canary lost: 256:171 @1280x1024 V-Int VGA gave {kind} {w}x{h}, "
      "expected the historical 1437-wide overflow")
kind, w, h = scale_int(1024, 768, 1, 512, 384, 256, 171)
check(kind == 'size' and w == 1149 and w > 1024,
      f"canary lost: 256:171 @1024x768 V-Int 12\" gave {kind} {w}x{h}, "
      "expected the historical 1149-wide overflow")

if FAIL:
    print(f"\naspect_check: {len(FAIL)} failure(s)")
    sys.exit(1)
print("aspect_check: all checks passed "
      f"({len(PANELS)*len(SOURCES)*len(MODES)} combos + table + canaries)")
