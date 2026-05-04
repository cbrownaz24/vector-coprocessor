#!/usr/bin/env python3
"""
gen_scaling_benchmarks.py - gens parameterized daxpy-N and linpack-NxN
.S bench files for the scaling study.

writes to tests/riscv/. each file is self contained and includes its
own test data. both scalar + vec variants made for each size.
"""

from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TESTS_DIR = REPO / "tests" / "riscv"

# ---------------------------------------------------------------------------
# daxpy-N: y[i] = a * x[i] + y[i] for i in 0..N-1
# strip-mined so 1 kernel works for any N (>VLMAX -> multi passes)
# ---------------------------------------------------------------------------

def daxpy_data(n: int) -> tuple[list[int], list[int], int, int, int]:
    """returns (x_data, y_data, a, expected_y0, expected_yN-1)"""
    x = [(i + 1) for i in range(n)]
    y = [(100 + i) for i in range(n)]
    a = 3
    expected_first = a * x[0] + y[0]
    expected_last  = a * x[n-1] + y[n-1]
    return x, y, a, expected_first, expected_last


def fmt_words(values: list[int], per_line: int = 8) -> str:
    out = []
    for i in range(0, len(values), per_line):
        chunk = ", ".join(f"{v:4d}" for v in values[i:i+per_line])
        out.append(f"        .word {chunk}")
    return "\n".join(out)


def daxpy_scalar(n: int) -> str:
    x, y, a, exp_first, exp_last = daxpy_data(n)
    return f"""//=========================================================================
// riscv-bmark-daxpy-scalar-N{n}.S - Scalar DAXPY at N={n}
//=========================================================================
// y[i] = a*x[i] + y[i] for i = 0..{n-1}; auto-generated.

#include "riscv-macros.h"

        TEST_RISCV_BEGIN

        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

        la    x10, x_data
        la    x11, y_data
        li    x12, {a}
        li    x13, {n}

        li    x5, 0
loop:
        lw    x14, 0(x10)
        lw    x15, 0(x11)
        mul   x16, x14, x12
        add   x16, x16, x15
        sw    x16, 0(x11)
        addi  x10, x10, 4
        addi  x11, x11, 4
        addi  x5, x5, 1
        bne   x5, x13, loop

        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        la    x11, y_data
        lw    x14, 0(x11)
        TEST_CHECK_EQ(x14, {exp_first})
        lw    x14, {(n-1)*4}(x11)
        TEST_CHECK_EQ(x14, {exp_last})

        TEST_RISCV_END

        .data
        .align 4
x_data:
{fmt_words(x)}
y_data:
{fmt_words(y)}
"""


def daxpy_vector(n: int) -> str:
    """strip-mined vec daxpy for any N (assumes VLMAX=32)"""
    x, y, a, exp_first, exp_last = daxpy_data(n)
    return f"""//=========================================================================
// riscv-bmark-daxpy-vector-N{n}.S - Vector DAXPY at N={n}
//=========================================================================
// Strip-mined: each iteration handles up to VLMAX={32} elements.

#include "riscv-macros.h"
#include "riscv-vec-macros.h"

        TEST_RISCV_BEGIN

        // CVM (default mask = all 1s)
        li    x13, {min(n,32)}
        SETVL(14, 13)
        VFENCE()
        CVM()
        VFENCE()

        la    x10, x_data
        la    x11, y_data
        li    x12, {a}
        li    x6, {n}                     // remaining

        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

strip_loop:
        SETVL(14, 6)                    // VL = min(remaining, VLMAX)
        VFENCE()
        VLW(0, 10)                      // v0 = x[strip]
        VLW(1, 11)                      // v1 = y[strip]
        VSMUL(2, 0, 12)                 // v2 = a*v0
        VVADD(3, 2, 1)                  // v3 = v2 + v1
        VSW(3, 11)                      // y[strip] = v3
        VFENCE()

        slli  x15, x14, 2               // bytes = VL * 4
        add   x10, x10, x15
        add   x11, x11, x15
        sub   x6, x6, x14
        bnez  x6, strip_loop

        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        la    x11, y_data
        lw    x14, 0(x11)
        TEST_CHECK_EQ(x14, {exp_first})
        lw    x14, {(n-1)*4}(x11)
        TEST_CHECK_EQ(x14, {exp_last})

        TEST_RISCV_END

        .data
        .align 4
x_data:
{fmt_words(x)}
y_data:
{fmt_words(y)}
"""


# ---------------------------------------------------------------------------
# linpack NxN: y = A * x  (matvec, square A)
# vec ver: VLW+VVMUL+VREDSUM per row (assumes N <= VLMAX so 1 row fits
# in one vec). scalar is a nested loop.
# ---------------------------------------------------------------------------

def linpack_data(n: int) -> tuple[list[list[int]], list[int], list[int]]:
    A = [[i*n + j + 1 for j in range(n)] for i in range(n)]
    x = [1] * n
    y = [sum(row) for row in A]   # x is all 1s so y[i] = row sum
    return A, x, y


def linpack_scalar(n: int) -> str:
    A, x, y = linpack_data(n)
    flat_A = [v for row in A for v in row]
    expected_first = y[0]
    expected_last  = y[n-1]
    row_bytes = n * 4
    return f"""//=========================================================================
// riscv-bmark-linpack-scalar-{n}x{n}.S - Scalar matvec, N={n}
//=========================================================================

#include "riscv-macros.h"

        TEST_RISCV_BEGIN

        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

        la    x10, A_data
        la    x11, x_data
        la    x12, y_data
        li    x13, {n}

        li    x5, 0
outer:
        li    x6, 0
        slli  x7, x5, {(row_bytes).bit_length()-1}
        add   x7, x10, x7
        mv    x8, x11
        li    x9, 0
inner:
        lw    x14, 0(x7)
        lw    x15, 0(x8)
        mul   x16, x14, x15
        add   x6, x6, x16
        addi  x7, x7, 4
        addi  x8, x8, 4
        addi  x9, x9, 1
        bne   x9, x13, inner

        slli  x17, x5, 2
        add   x17, x12, x17
        sw    x6, 0(x17)

        addi  x5, x5, 1
        bne   x5, x13, outer

        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        la    x12, y_data
        lw    x14, 0(x12)
        TEST_CHECK_EQ(x14, {expected_first})
        lw    x14, {(n-1)*4}(x12)
        TEST_CHECK_EQ(x14, {expected_last})

        TEST_RISCV_END

        .data
        .align 4
A_data:
{fmt_words(flat_A, per_line=n if n<=16 else 16)}
x_data:
{fmt_words(x)}
y_data:
        .space {n*4}
"""


def linpack_vector(n: int) -> str:
    """vec matvec: load x once, then per row VLW+VVMUL+VREDSUM+SW"""
    A, x, y = linpack_data(n)
    flat_A = [v for row in A for v in row]
    expected_first = y[0]
    expected_last  = y[n-1]
    row_bytes = n * 4
    return f"""//=========================================================================
// riscv-bmark-linpack-vector-{n}x{n}.S - Vector matvec, N={n}
//=========================================================================
// Each row: VLW + VVMUL + VREDSUM + scalar SW. Per-row VFENCE because
// scalar reads the reduction result before issuing the next iteration.

#include "riscv-macros.h"
#include "riscv-vec-macros.h"

        TEST_RISCV_BEGIN

        li    x13, {n}
        SETVL(14, 13)
        VFENCE()
        CVM()
        VFENCE()

        la    x11, x_data
        la    x12, y_data

        VLW(0, 11)
        VFENCE()

        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

        la    x10, A_data
        li    x5, 0
        li    x6, {n}
row_loop:
        VLW(1, 10)
        VVMUL(2, 0, 1)
        VREDSUM(16, 2)
        VFENCE()
        sw    x16, 0(x12)

        addi  x10, x10, {row_bytes}
        addi  x12, x12, 4
        addi  x5, x5, 1
        bne   x5, x6, row_loop

        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        la    x12, y_data
        lw    x14, 0(x12)
        TEST_CHECK_EQ(x14, {expected_first})
        lw    x14, {(n-1)*4}(x12)
        TEST_CHECK_EQ(x14, {expected_last})

        TEST_RISCV_END

        .data
        .align 4
A_data:
{fmt_words(flat_A, per_line=n if n<=16 else 16)}
x_data:
{fmt_words(x)}
y_data:
        .space {n*4}
"""


# ---------------------------------------------------------------------------
# pipelined linpack 16x16: drop per-row VFENCE so queue can fill.
# each row's reduction lands in a *diff* scalar reg (x16..x31), then 1
# VFENCE at end drains everything before scalar stores y[0..15].
# ---------------------------------------------------------------------------

def linpack_pipelined_16() -> str:
    n = 16
    A, x, y = linpack_data(n)
    flat_A = [v for row in A for v in row]
    expected_first = y[0]
    expected_last  = y[n-1]
    # per-row body: VLW (load row) + VVMUL + VREDSUM into uniqe reg
    body = []
    for i in range(n):
        rd = 16 + i  # x16..x31
        body.append(f"        VLW(1, 10)")
        body.append(f"        VVMUL(2, 0, 1)")
        body.append(f"        VREDSUM({rd}, 2)")
        body.append(f"        addi  x10, x10, {n*4}")
    body_text = "\n".join(body)
    # after fence, dump all regs to y[]
    stores = []
    for i in range(n):
        rd = 16 + i
        stores.append(f"        sw    x{rd}, {i*4}(x12)")
    store_text = "\n".join(stores)
    return f"""//=========================================================================
// riscv-bmark-linpack-pipelined-16x16.S - Vector matvec WITHOUT per-row fence
//=========================================================================
// Each row's reduction lands in a unique scalar register (x16..x31), so
// the scalar core can keep pushing the next row's vector ops without
// waiting. Single VFENCE at the very end. Designed to actually exercise
// command queue depth.

#include "riscv-macros.h"
#include "riscv-vec-macros.h"

        TEST_RISCV_BEGIN

        li    x13, {n}
        SETVL(14, 13)
        VFENCE()
        CVM()
        VFENCE()

        la    x11, x_data
        la    x12, y_data
        VLW(0, 11)
        VFENCE()

        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

        la    x10, A_data
{body_text}
        VFENCE()                        // single drain

        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        // Now flush all reductions to memory
        la    x12, y_data
{store_text}

        // Verify
        la    x12, y_data
        lw    x14, 0(x12)
        TEST_CHECK_EQ(x14, {expected_first})
        lw    x14, {(n-1)*4}(x12)
        TEST_CHECK_EQ(x14, {expected_last})

        TEST_RISCV_END

        .data
        .align 4
A_data:
{fmt_words(flat_A, per_line=n)}
x_data:
{fmt_words(x)}
y_data:
        .space {n*4}
"""


# ---------------------------------------------------------------------------
# chain depth study: N consecutive RAW-dep VVADDs.
#
# for each depth N, kernel does:
#     v_{i+1} = v_i + v_const   for i = 0..N-1
# all VVADDs share addend v1 = ones, and result of one feeds src of the
# next so we get a perfect RAW chain. after N adds, result is x + N.
# limit 6 since we have v0..v7 (v0/v1 inputs, v2..v7 for chain).
# ---------------------------------------------------------------------------

def chain_depth_kernel(depth: int, vl: int = 8) -> str:
    """gen kernel with `depth` consec RAW-dep VVADDs"""
    if depth < 1 or depth > 6:
        raise ValueError("chain depth must be 1..6")
    x = [(i + 1) for i in range(vl)]            # 1, 2, ..., vl
    y_addend = [1] * vl                         # const 1s
    expected = [x[i] + depth for i in range(vl)]

    body_lines = []
    src = 0   # vreg holding curr chain val
    for i in range(depth):
        dst = 2 + i      # v2, v3, v4, ...
        body_lines.append(f"        VVADD({dst}, {src}, 1)        // step {i+1}: v{dst} = v{src} + v1")
        src = dst
    body = "\n".join(body_lines)
    final_dst = 2 + depth - 1

    return f"""//=========================================================================
// riscv-bmark-chain-depth-{depth}.S - {depth} consecutive chainable VVADDs
//=========================================================================
// v0 = x_data, v1 = ones; then run {depth} VVADDs each RAW-dependent on
// the previous. Each VVADD chains with its immediate successor on the
// chaining design; on the master design they execute serially.

#include "riscv-macros.h"
#include "riscv-vec-macros.h"

        TEST_RISCV_BEGIN

        li    x13, {vl}
        SETVL(14, 13)
        VFENCE()
        CVM()
        VFENCE()

        la    x10, x_data
        la    x11, ones_data
        VLW(0, 10)
        VLW(1, 11)
        VFENCE()

        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

{body}

        // Drain and store
        la    x12, dst_data
        VSW({final_dst}, 12)
        VFENCE()

        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        // Verify two elements: result[0] = 1 + depth, result[VL-1] = VL + depth
        la    x12, dst_data
        lw    x14, 0(x12)
        TEST_CHECK_EQ(x14, {expected[0]})
        lw    x14, {(vl-1)*4}(x12)
        TEST_CHECK_EQ(x14, {expected[vl-1]})

        TEST_RISCV_END

        .data
        .align 4
x_data:
{fmt_words(x)}
ones_data:
{fmt_words(y_addend)}
dst_data:
        .space {vl*4}
"""


CHAIN_DEPTHS = [1, 2, 3, 4, 5, 6]


# ---------------------------------------------------------------------------
# driver
# ---------------------------------------------------------------------------

DAXPY_SIZES   = [16, 32, 64, 128, 256]
LINPACK_SIZES = [4, 8, 16, 32]


def main() -> None:
    written: list[str] = []
    for n in DAXPY_SIZES:
        (TESTS_DIR / f"riscv-bmark-daxpy-scalar-N{n}.S").write_text(daxpy_scalar(n))
        (TESTS_DIR / f"riscv-bmark-daxpy-vector-N{n}.S").write_text(daxpy_vector(n))
        written.append(f"daxpy-N{n}")
    for n in LINPACK_SIZES:
        (TESTS_DIR / f"riscv-bmark-linpack-scalar-{n}x{n}.S").write_text(linpack_scalar(n))
        (TESTS_DIR / f"riscv-bmark-linpack-vector-{n}x{n}.S").write_text(linpack_vector(n))
        written.append(f"linpack-{n}x{n}")
    (TESTS_DIR / "riscv-bmark-linpack-pipelined-16x16.S").write_text(linpack_pipelined_16())
    written.append("linpack-pipelined-16x16")
    for d in CHAIN_DEPTHS:
        (TESTS_DIR / f"riscv-bmark-chain-depth-{d}.S").write_text(chain_depth_kernel(d))
        written.append(f"chain-depth-{d}")
    for w in written:
        print(f"wrote {w}")


if __name__ == "__main__":
    main()
