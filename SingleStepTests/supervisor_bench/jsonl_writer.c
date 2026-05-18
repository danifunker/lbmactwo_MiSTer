#include "jsonl_writer.h"
#include "freestanding.h"

/* IOParam offsets (Inside Macintosh: Files) */
#define PB_OFF_IORESULT     16
#define PB_OFF_IOVREFNUM    22
#define PB_OFF_IOREFNUM     24
#define PB_OFF_IOBUFFER     32
#define PB_OFF_IOREQCOUNT   36
#define PB_OFF_IOACTCOUNT   40
#define PB_OFF_IOPOSMODE    44
#define PB_OFF_IOPOSOFFSET  46
#define PB_SIZE             80

static u8 g_pb[PB_SIZE];

/* Single-sector _Write at byte offset (ctx.base_offset + sector_idx * 512).
 * Returns ioResult (0 = noErr). Inline asm calls $A003 _Write. */
extern void paint_string(u32 row, u32 col_byte, const char *s, u32 max_chars);
static void pmk(char c) { char s[2]; s[0]=c; s[1]=0; paint_string(50, 7, s, 1); }

static i16 driver_write_sector(const JwCtx *ctx, u32 sector_idx, const u8 *buf)
{
    u8 *pb = g_pb;
    u32 i;
    pmk('a');
    for (i = 0; i < PB_SIZE; i++) pb[i] = 0;
    pmk('b');
    *(i16 *)(pb + PB_OFF_IOREFNUM)   = ctx->refnum;
    *(i16 *)(pb + PB_OFF_IOVREFNUM)  = ctx->drive;
    *(u32 *)(pb + PB_OFF_IOBUFFER)   = (u32)buf;
    *(u32 *)(pb + PB_OFF_IOREQCOUNT) = 512;
    *(i16 *)(pb + PB_OFF_IOPOSMODE)  = 1;     /* fsFromStart */
    *(u32 *)(pb + PB_OFF_IOPOSOFFSET) = ctx->base_offset + sector_idx * 512;
    pmk('c');

    asm volatile (
        "movel %0, %%a0   \n"
        ".short 0xA003    \n"   /* _Write */
        :
        : "g" (pb)
        : "a0", "a1", "d0", "d1", "d2", "cc", "memory"
    );

    pmk('d');
    return *(i16 *)(pb + PB_OFF_IORESULT);
}

void jw_init(JsonlWriter *w, const JwCtx *ctx)
{
    f_memset(w, 0, sizeof(*w));
    w->ctx = *ctx;
}

static void flush_sector(JsonlWriter *w)
{
    /* Zero-pad anything not written in this sector. */
    if (w->used < 512) f_memset(w->sector + w->used, 0, 512 - w->used);
    u32 sector_idx = w->written / 512;
    i16 r = driver_write_sector(&w->ctx, sector_idx, w->sector);
    if (r != 0 && w->last_err == 0) w->last_err = r;
    w->written += 512;
    w->used = 0;
}

void jw_putc(JsonlWriter *w, char c)
{
    if (w->written + w->used >= w->ctx.max_bytes) return;  /* full */
    w->sector[w->used++] = (u8)c;
    if (w->used == 512) flush_sector(w);
}

void jw_puts(JsonlWriter *w, const char *s)
{
    while (*s) jw_putc(w, *s++);
}

void jw_putul(JsonlWriter *w, u32 v)
{
    char tmp[12];
    char *t = f_putul(tmp, v);
    char *p;
    for (p = tmp; p < t; p++) jw_putc(w, *p);
}

/* Same as flush_sector but does not advance the sector pointer. */
extern void paint_string(u32 row, u32 col_byte, const char *s, u32 max_chars);

static void paint_marker(char c)
{
    char s[2];
    s[0] = c; s[1] = '\0';
    paint_string(50, 6, s, 1);
}

void jw_commit_line(JsonlWriter *w)
{
    paint_marker('1');
    if (w->written + w->used >= w->ctx.max_bytes) { paint_marker('!'); return; }
    paint_marker('2');
    if (w->used < 512) f_memset(w->sector + w->used, 0, 512 - w->used);
    paint_marker('3');
    u32 sector_idx = w->written / 512;
    i16 r = driver_write_sector(&w->ctx, sector_idx, w->sector);
    paint_marker('4');
    if (r != 0 && w->last_err == 0) w->last_err = r;
    paint_marker('5');
}

void jw_flush(JsonlWriter *w)
{
    if (w->used > 0) flush_sector(w);
}
