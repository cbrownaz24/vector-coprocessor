//=========================================================================
// riscv-bmark-linpack-scalar-4x4.S - Scalar matvec, N=4
//=========================================================================

#include "riscv-macros.h"

        TEST_RISCV_BEGIN

        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

        la    x10, A_data
        la    x11, x_data
        la    x12, y_data
        li    x13, 4

        li    x5, 0
outer:
        li    x6, 0
        slli  x7, x5, 4
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
