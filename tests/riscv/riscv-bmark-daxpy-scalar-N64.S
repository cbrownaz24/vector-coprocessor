//=========================================================================
// riscv-bmark-daxpy-scalar-N64.S - Scalar DAXPY at N=64
//=========================================================================
// y[i] = a*x[i] + y[i] for i = 0..63; auto-generated.

#include "riscv-macros.h"

        TEST_RISCV_BEGIN

        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

        la    x10, x_data
        la    x11, y_data
        li    x12, 3
        li    x13, 64

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
        lw    x14, 252(x11)
        TEST_CHECK_EQ(x14, 355)

        TEST_RISCV_END

        .data
        .align 4
x_data:
        .word    1,    2,    3,    4,    5,    6,    7,    8
        .word    9,   10,   11,   12,   13,   14,   15,   16
        .word   17,   18,   19,   20,   21,   22,   23,   24
        .word   25,   26,   27,   28,   29,   30,   31,   32
        .word   33,   34,   35,   36,   37,   38,   39,   40
        .word   41,   42,   43,   44,   45,   46,   47,   48
        .word   49,   50,   51,   52,   53,   54,   55,   56
        .word   57,   58,   59,   60,   61,   62,   63,   64
y_data:
        .word  100,  101,  102,  103,  104,  105,  106,  107
        .word  108,  109,  110,  111,  112,  113,  114,  115
        .word  116,  117,  118,  119,  120,  121,  122,  123
        .word  124,  125,  126,  127,  128,  129,  130,  131
        .word  132,  133,  134,  135,  136,  137,  138,  139
        .word  140,  141,  142,  143,  144,  145,  146,  147
        .word  148,  149,  150,  151,  152,  153,  154,  155
        .word  156,  157,  158,  159,  160,  161,  162,  163
