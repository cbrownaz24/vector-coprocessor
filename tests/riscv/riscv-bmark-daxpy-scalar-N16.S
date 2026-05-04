//=========================================================================
// riscv-bmark-daxpy-scalar-N16.S - Scalar DAXPY at N=16
//=========================================================================
// y[i] = a*x[i] + y[i] for i = 0..15; auto-generated.

#include "riscv-macros.h"

        TEST_RISCV_BEGIN

        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

        la    x10, x_data
        la    x11, y_data
        li    x12, 3
        li    x13, 16

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
        TEST_CHECK_EQ(x14, 103)
        lw    x14, 60(x11)
        TEST_CHECK_EQ(x14, 163)

        TEST_RISCV_END

        .data
        .align 4
x_data:
        .word    1,    2,    3,    4,    5,    6,    7,    8
        .word    9,   10,   11,   12,   13,   14,   15,   16
y_data:
        .word  100,  101,  102,  103,  104,  105,  106,  107
        .word  108,  109,  110,  111,  112,  113,  114,  115
