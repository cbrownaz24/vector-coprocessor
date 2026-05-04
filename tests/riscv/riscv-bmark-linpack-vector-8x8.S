//=========================================================================
// riscv-bmark-linpack-vector-8x8.S - Vector matvec, N=8
//=========================================================================
// Each row: VLW + VVMUL + VREDSUM + scalar SW. Per-row VFENCE because
// scalar reads the reduction result before issuing the next iteration.

#include "riscv-macros.h"
#include "riscv-vec-macros.h"

        TEST_RISCV_BEGIN

        li    x13, 8
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
        li    x6, 8
row_loop:
        VLW(1, 10)
        VVMUL(2, 0, 1)
        VREDSUM(16, 2)
        VFENCE()
        sw    x16, 0(x12)

        addi  x10, x10, 32
        addi  x12, x12, 4
        addi  x5, x5, 1
        bne   x5, x6, row_loop

        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        la    x12, y_data
        lw    x14, 0(x12)
        TEST_CHECK_EQ(x14, 36)
        lw    x14, 28(x12)
        TEST_CHECK_EQ(x14, 484)

        TEST_RISCV_END

        .data
        .align 4
A_data:
        .word    1,    2,    3,    4,    5,    6,    7,    8
        .word    9,   10,   11,   12,   13,   14,   15,   16
        .word   17,   18,   19,   20,   21,   22,   23,   24
        .word   25,   26,   27,   28,   29,   30,   31,   32
        .word   33,   34,   35,   36,   37,   38,   39,   40
        .word   41,   42,   43,   44,   45,   46,   47,   48
        .word   49,   50,   51,   52,   53,   54,   55,   56
        .word   57,   58,   59,   60,   61,   62,   63,   64
x_data:
        .word    1,    1,    1,    1,    1,    1,    1,    1
y_data:
        .space 32
