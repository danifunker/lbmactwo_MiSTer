cmake_minimum_required(VERSION 3.10)
project(MacOsBench C CXX)

# Three Mac OS APPLs in this directory:
#   CpuBench        — user-mode CPU instruction tests (~676 tests from cpu_tests.h)
#   FpuBench        — 68881 FPU tests (~270 tests from fpu_tests.h)
#   CpuFpuBench     — CPU+FPU integration tests (1328 tests from fpu_corpus_baseline.json)

add_application(CpuBench CONSOLE
    cpu_bench.c
    cpubench.r
    CREATOR CpuB
)

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
