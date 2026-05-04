//=========================================================================
// riscv-bmark-linpack-scalar.S - LINPACK-kernel matrix-vector multiply
//=========================================================================
// Computes y = A * x where A is 16x16 and x, y are 16-vectors.
// Pure scalar implementation: nested loop, 16*16=256 mul/add steps.
// This is the inner kernel of dense linear-algebra benchmarks (DGEMV).

#include "riscv-macros.h"

#define N 16

        TEST_RISCV_BEGIN

        // Stats on
        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

        la    x10, A_data       // base of A
        la    x11, x_data       // base of x
        la    x12, y_data       // base of y
        li    x13, N            // outer/inner loop bound

        li    x5, 0             // i = 0
outer_loop:
        // acc = 0
        li    x6, 0             // acc

        // row pointer: A_data + i*N*4
        slli  x7, x5, 6         // i * 16 * 4 = i*64
        add   x7, x10, x7       // &A[i][0]

        // x pointer
        mv    x8, x11           // &x[0]

        li    x9, 0             // j = 0
inner_loop:
        lw    x14, 0(x7)        // A[i][j]
        lw    x15, 0(x8)        // x[j]
        mul   x16, x14, x15     // multiply
        add   x6, x6, x16       // acc += ...
        addi  x7, x7, 4
        addi  x8, x8, 4
        addi  x9, x9, 1
        bne   x9, x13, inner_loop

        // y[i] = acc
        slli  x17, x5, 2        // i*4
        add   x17, x12, x17     // &y[i]
        sw    x6, 0(x17)

        addi  x5, x5, 1
        bne   x5, x13, outer_loop

        // Stats off
        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        // Verify a few elements:
        //   y[0]  = sum(A[0][j]*x[j])  = sum(1..16)    = 136
        //   y[15] = sum(A[15][j]*x[j]) = sum(241..256) = 3976
        la    x12, y_data
        lw    x14, 0(x12)
        TEST_CHECK_EQ(x14, 136)
        lw    x14, 60(x12)              // y[15]
        TEST_CHECK_EQ(x14, 3976)

        TEST_RISCV_END

        .data
        .align 4
// A is 16x16 row-major. A[i][j] = i*N + j + 1
// So row 0 = 1..16, row 1 = 17..32, ..., row 15 = 241..256
A_data:
        .word   1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15, 16
        .word  17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32
        .word  33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48
        .word  49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64
        .word  65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80
        .word  81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96
        .word  97, 98, 99,100,101,102,103,104,105,106,107,108,109,110,111,112
        .word 113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128
        .word 129,130,131,132,133,134,135,136,137,138,139,140,141,142,143,144
        .word 145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,160
        .word 161,162,163,164,165,166,167,168,169,170,171,172,173,174,175,176
        .word 177,178,179,180,181,182,183,184,185,186,187,188,189,190,191,192
        .word 193,194,195,196,197,198,199,200,201,202,203,204,205,206,207,208
        .word 209,210,211,212,213,214,215,216,217,218,219,220,221,222,223,224
        .word 225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,240
        .word 241,242,243,244,245,246,247,248,249,250,251,252,253,254,255,256

// x is all 1s, so y[i] = sum of A's row i
x_data:
        .word 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1

y_data:
        .space 64
