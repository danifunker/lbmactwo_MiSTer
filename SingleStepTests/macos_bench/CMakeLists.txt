cmake_minimum_required(VERSION 3.10)
project(MacOsBench C CXX)

# Three Mac OS APPLs in this directory:
#   CpuBench        — user-mode CPU instruction tests (~676 tests from cpu_tests.h)
#   FpuBench        — 68881 FPU tests (~270 tests from fpu_tests.h)
#   CpuFpuBench     — CPU+FPU integration tests (1328 tests from fpu_corpus_baseline.json)

# Which CPU corpus header CpuBench compiles in. Point it at a filtered
# header (see gen/filter_cpu_tests_h.py) to leave tests out of the binary:
#   cmake -DCPU_CORPUS_HEADER=../gen/cpu_tests_nogroup0.h ..
# Path is relative to macos_bench/ (cpu_bench.c includes it directly).
set(CPU_CORPUS_HEADER "../gen/cpu_tests.h" CACHE STRING
    "CPU corpus header compiled into CpuBench")

add_application(CpuBench CONSOLE
    cpu_bench.c
    cpubench.r
    CREATOR CpuB
)
target_compile_definitions(CpuBench PRIVATE
    CPU_CORPUS_HEADER="${CPU_CORPUS_HEADER}")

add_application(FpuBench CONSOLE
    fpu_bench.c
    fpubench.r
    CREATOR FpuB
)

add_application(CpuFpuBench CONSOLE
    cpu_fpu_bench.c
    cpufpubench.r
    CREATOR CFpB
)
