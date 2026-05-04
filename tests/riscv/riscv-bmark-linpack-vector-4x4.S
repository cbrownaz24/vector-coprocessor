//=========================================================================
// riscv-bmark-linpack-vector-4x4.S - Vector matvec, N=4
//=========================================================================
// Each row: VLW + VVMUL + VREDSUM + scalar SW. Per-row VFENCE because
// scalar reads the reduction result before issuing the next iteration.

#include "riscv-macros.h"
#include "riscv-vec-macros.h"

        TEST_RISCV_BEGIN

        li    x13, 4
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
        li    x6, 4
row_loop:
        VLW(1, 10)
        VVMUL(2, 0, 1)
        VREDSUM(16, 2)
        VFENCE()
        sw    x16, 0(x12)

        addi  x10, x10, 16
        addi  x12, x12, 4
        addi  x5, x5, 1
        bne   x5, x6, row_loop

        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        la    x12, y_data
        lw    x14, 0(x12)
        TEST_CHECK_EQ(x14, 10)
        lw    x14, 12(x12)
        TEST_CHECK_EQ(x14, 58)

        TEST_RISCV_END

        .data
        .align 4
A_data:
        .word    1,    2,    3,    4
        .word    5,    6,    7,    8
        .word    9,   10,   11,   12
        .word   13,   14,   15,   16
x_data:
        .word    1,    1,    1,    1
y_data:
        .space 16
