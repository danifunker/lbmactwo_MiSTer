#ifndef JSONL_WRITER_H
#define JSONL_WRITER_H

#include <stdint.h>

typedef int16_t jw_refnum_t;

jw_refnum_t jw_open(const char *mac_path);
int         jw_write(jw_refnum_t r, const char *buf, int32_t len);
int         jw_close(jw_refnum_t r);

#endif
