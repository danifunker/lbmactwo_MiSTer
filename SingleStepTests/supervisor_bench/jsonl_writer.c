/* Step F: minimal _Open/_Write/_SetEOF/_Close wrapper, no stdio.
 * Stub bodies for now so the skeleton links. */

#include "jsonl_writer.h"

jw_refnum_t jw_open(const char *mac_path) {
    (void)mac_path;
    return -1;
}

int jw_write(jw_refnum_t r, const char *buf, int32_t len) {
    (void)r; (void)buf; (void)len;
    return -1;
}

int jw_close(jw_refnum_t r) {
    (void)r;
    return -1;
}
