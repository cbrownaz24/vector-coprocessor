//=========================================================================
// riscv-bmark-linpack-scalar-8x8.S - Scalar matvec, N=8
//=========================================================================

#include "riscv-macros.h"

        TEST_RISCV_BEGIN

        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

        la    x10, A_data
        la    x11, x_data
        la    x12, y_data
        li    x13, 8

        li    x5, 0
outer:
        li    x6, 0
        slli  x7, x5, 5
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
