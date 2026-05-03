//=========================================================================
// riscv-bmark-chain-depth-6.S - 6 consecutive chainable VVADDs
//=========================================================================
// v0 = x_data, v1 = ones; then run 6 VVADDs each RAW-dependent on
// the previous. Each VVADD chains with its immediate successor on the
// chaining design; on the master design they execute serially.

#include "riscv-macros.h"
#include "riscv-vec-macros.h"

        TEST_RISCV_BEGIN

        li    x13, 8
        SETVL(14, 13)
        VFENCE()
        CVM()
        VFENCE()

        la    x10, x_data
        la    x11, ones_data
        VLW(0, 10)
        VLW(1, 11)
        VFENCE()

        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

        VVADD(2, 0, 1)        // step 1: v2 = v0 + v1
        VVADD(3, 2, 1)        // step 2: v3 = v2 + v1
        VVADD(4, 3, 1)        // step 3: v4 = v3 + v1
        VVADD(5, 4, 1)        // step 4: v5 = v4 + v1
        VVADD(6, 5, 1)        // step 5: v6 = v5 + v1
        VVADD(7, 6, 1)        // step 6: v7 = v6 + v1

        // Drain and store
        la    x12, dst_data
        VSW(7, 12)
        VFENCE()

        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        // Verify two elements: result[0] = 1 + depth, result[VL-1] = VL + depth
        la    x12, dst_data
        lw    x14, 0(x12)
        TEST_CHECK_EQ(x14, 7)
        lw    x14, 28(x12)
        TEST_CHECK_EQ(x14, 14)

        TEST_RISCV_END

        .data
        .align 4
x_data:
        .word    1,    2,    3,    4,    5,    6,    7,    8
ones_data:
        .word    1,    1,    1,    1,    1,    1,    1,    1
dst_data:
        .space 32
