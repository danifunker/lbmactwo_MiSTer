/* eject.c — shared floppy-eject helper for preboot benches.
 *
 * Issues a Device Manager _Control trap (A004) to the .Sony floppy
 * driver (refnum -5) with csCode 7 (eject). Self-contained: builds the
 * CntrlParam block from a raw 80-byte buffer by field offset so it
 * doesn't depend on any bench's own ParamBlock typedef.
 *
 * CntrlParam field offsets (Inside Macintosh: Devices):
 *   24  ioCRefNum (word)  -- driver refnum (.Sony = -5)
 *   26  csCode    (word)  -- 7 = eject
 *   28  csParam[] (...)   -- csParam[0] (word) = drive number
 */

#include "eject.h"

static i16 trap_control(void *pb)
{
    register i16  r asm("d0");
    register void *p asm("a0") = pb;
    asm volatile (".word 0xA004\n"
                  : "=d"(r)
                  : "a"(p)
                  : "d1", "d2", "a1", "cc", "memory");
    return r;
}

i16 eject_floppy(i16 drive)
{
    u8 pb[80];
    u32 i;
    for (i = 0; i < sizeof(pb); i++) pb[i] = 0;

    /* ioCRefNum (word, big-endian) = -5 (.Sony) */
    pb[24] = 0xFF;
    pb[25] = 0xFB;
    /* csCode (word) = 7 (eject) */
    pb[26] = 0x00;
    pb[27] = 0x07;
    /* csParam[0] (word) = drive number */
    pb[28] = (u8)((drive >> 8) & 0xFF);
    pb[29] = (u8)( drive       & 0xFF);

    return trap_control(pb);
}
