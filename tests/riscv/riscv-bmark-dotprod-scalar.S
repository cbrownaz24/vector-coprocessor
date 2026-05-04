//=========================================================================
// riscv-bmark-dotprod-scalar.S - Scalar dot product (32 elements)
//=========================================================================
// result = sum( a[i] * b[i] ) for i = 0..31
// Scalar baseline: explicit loop with MUL stall each iteration.

#include "riscv-macros.h"
#include "riscv-vec-macros.h"

        TEST_RISCV_BEGIN

        la    x10, a_data      // a array pointer
        la    x11, b_data      // b array pointer
        li    x12, 0           // accumulator
        li    x13, 32          // loop count

        // Stats on
        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

1:      lw    x14, 0(x10)     // load a[i]
        lw    x15, 0(x11)     // load b[i]
        mul   x16, x14, x15   // a[i] * b[i]  <- MUL stall
        add   x12, x12, x16   // accumulate
        addi  x10, x10, 4
        addi  x11, x11, 4
        addi  x13, x13, -1
        bne   x13, x0, 1b

        // Stats off
        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        // Verify: sum(i^2 for i=1..32) = 32*33*65/6 = 11440
        TEST_CHECK_EQ(x12, 11440)

        TEST_RISCV_END

        .data
        .align 4
a_data:
        .word  1,  2,  3,  4,  5,  6,  7,  8
        .word  9, 10, 11, 12, 13, 14, 15, 16
        .word 17, 18, 19, 20, 21, 22, 23, 24
        .word 25, 26, 27, 28, 29, 30, 31, 32
b_data:
        .word  1,  2,  3,  4,  5,  6,  7,  8
        .word  9, 10, 11, 12, 13, 14, 15, 16
        .word 17, 18, 19, 20, 21, 22, 23, 24
        .word 25, 26, 27, 28, 29, 30, 31, 32
