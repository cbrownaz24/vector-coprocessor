//=========================================================================
// riscv-bmark-daxpy-scalar.S - Scalar DAXPY benchmark (32 elements)
//=========================================================================
// y[i] = a * x[i] + y[i] for i=0..31
// Classic BLAS-1 kernel, pure scalar

#include "riscv-macros.h"

        TEST_RISCV_BEGIN

        la    x10, x_data      // x array
        la    x11, y_data      // y array
        li    x12, 3           // scalar a = 3
        li    x13, 32          // count

        // Stats on
        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

        // Scalar DAXPY loop
1:      lw    x14, 0(x10)     // load x[i]
        lw    x15, 0(x11)     // load y[i]
        mul   x16, x14, x12   // a * x[i]
        add   x16, x16, x15   // a*x[i] + y[i]
        sw    x16, 0(x11)     // store y[i]
        addi  x10, x10, 4
        addi  x11, x11, 4
        addi  x13, x13, -1
        bne   x13, x0, 1b

        // Stats off
        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        // Verify: y[0] = 3*1 + 100 = 103, y[31] = 3*32 + 131 = 227
        la    x11, y_data
        lw    x14, 0(x11)
        TEST_CHECK_EQ(x14, 103)
        lw    x14, 124(x11)
        TEST_CHECK_EQ(x14, 227)

        TEST_RISCV_END

        .data
        .align 4
x_data:
        .word 1, 2, 3, 4, 5, 6, 7, 8
        .word 9, 10, 11, 12, 13, 14, 15, 16
        .word 17, 18, 19, 20, 21, 22, 23, 24
        .word 25, 26, 27, 28, 29, 30, 31, 32
y_data:
        .word 100, 101, 102, 103, 104, 105, 106, 107
        .word 108, 109, 110, 111, 112, 113, 114, 115
        .word 116, 117, 118, 119, 120, 121, 122, 123
        .word 124, 125, 126, 127, 128, 129, 130, 131
