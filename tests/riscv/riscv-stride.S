//=========================================================================
// riscv-stride.S - strided mem access correctness tests
//=========================================================================
// hits VLWS (strided load) and VSWS (strided store) - paths that exist
// in hw but had no test coverage on master.

#include "riscv-macros.h"
#include "riscv-vec-macros.h"

        TEST_RISCV_BEGIN

        // vl=4 (small so bugs localize)
        li    x13, 4
        SETVL(14, 13)
        VFENCE()
        CVM()
        VFENCE()

        //=================================================================
        // t1: strided load, stride=8 (every other word)
        //=================================================================
        la    x10, src_strided
        li    x11, 8

        VLWS(0, 10, 11)
        VFENCE()

        // verify by storing v0 unit-stride + reading back
        la    x12, dst_unit
        VSW(0, 12)
        VFENCE()

        lw    x14, 0(x12)
        TEST_CHECK_EQ(x14, 1)
        lw    x14, 4(x12)
        TEST_CHECK_EQ(x14, 2)
        lw    x14, 8(x12)
        TEST_CHECK_EQ(x14, 3)
        lw    x14, 12(x12)
        TEST_CHECK_EQ(x14, 4)

        //=================================================================
        // t2: strided store, stride=8
        //=================================================================
        la    x10, src_seq
        VLW(1, 10)                      // v1 = {10,11,12,13}
        VFENCE()

        la    x12, dst_strided
        li    x11, 8
        VSWS(1, 12, 11)
        VFENCE()

        lw    x14, 0(x12)
        TEST_CHECK_EQ(x14, 10)
        lw    x14, 4(x12)
        TEST_CHECK_EQ(x14, 0)         // gap, unwritten
        lw    x14, 8(x12)
        TEST_CHECK_EQ(x14, 11)
        lw    x14, 16(x12)
        TEST_CHECK_EQ(x14, 12)
        lw    x14, 24(x12)
        TEST_CHECK_EQ(x14, 13)

        TEST_RISCV_END

        .data
        .align 4
src_strided:
        .word 1,99, 2,99, 3,99, 4,99

src_seq:
        .word 10, 11, 12, 13

dst_unit:
        .space 32

dst_strided:
        .space 64
