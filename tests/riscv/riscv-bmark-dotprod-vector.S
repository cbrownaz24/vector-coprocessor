//=========================================================================
// riscv-bmark-dotprod-vector.S - Vector dot product (32 elements)
//=========================================================================
// result = sum( a[i] * b[i] ) for i = 0..31
// Vector: VLW * 2, VVMUL, VREDSUM (reduction -> scalar), VFENCE

#include "riscv-macros.h"
#include "riscv-vec-macros.h"

        TEST_RISCV_BEGIN

        la    x10, a_data
        la    x11, b_data
        li    x13, 32
        SETVL(14, 13)           // VL = 32
        VFENCE()
        CVM()
        VFENCE()

        // Stats on
        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

        VLW(0, 10)              // v0 = a[0:31]
        VLW(1, 11)              // v1 = b[0:31]
        VVMUL(2, 0, 1)          // v2[i] = a[i] * b[i]
        VREDSUM(10, 2)          // x10 = sum(v2)
        VFENCE()

        // Stats off
        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        // Verify: sum(i^2) for i=1..32 = 11440... wait:
        // a[i]=i, b[i]=i => sum(i^2) for i=1..32 = 32*33*65/6 = 11440
        // But TEST_CHECK_EQ moves result from VREDSUM into x14 first
        // VREDSUM already wrote into x10, copy to x14 for check
        addi  x14, x10, 0
        TEST_CHECK_EQ(x14, 11440)

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
