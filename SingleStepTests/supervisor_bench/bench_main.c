/* bench_main.c — Step E. Supervisor-mode fork of cpu_test_macii.c.
 * Stub: just returns. Real impl iterates tests_cpu.h, runs each
 * via build_program/invoke_program, captures Snapshot via the
 * VBR handlers in exception_handlers.s, emits JSONL via jsonl_writer.
 */

#include <stdint.h>
#include "jsonl_writer.h"

void bench_main(void) {
    jw_refnum_t r = jw_open("Results.jsonl");
    (void)r;
    /* TODO Step E: iterate tests, run, write JSONL, _SetEOF, close. */
}
