//=========================================================================
// riscv-redsum.S - small test for VREDSUM
//=========================================================================

#include "riscv-macros.h"
#include "riscv-vec-macros.h"

        TEST_RISCV_BEGIN

        // vl = 4
        li    x13, 4
        SETVL(14, 13)
        VFENCE()
        CVM()
        VFENCE()

        // t1: VREDSUM of v0 = {1,2,3,4} -> 10
        la    x10, src1
        VLW(0, 10)
        VFENCE()
        VREDSUM(16, 0)
        VFENCE()
        TEST_CHECK_EQ(x16, 10)

        // t2: VREDSUM of v1 = {10,20,30,40} -> 100
        la    x10, src2
        VLW(1, 10)
        VFENCE()
        VREDSUM(17, 1)
        VFENCE()
        TEST_CHECK_EQ(x17, 100)

        // t3: VREDSUM after VVMUL
        // v2 = v0*v1 = {10,40,90,160}, sum = 300
        VVMUL(2, 0, 1)
        VFENCE()
        VREDSUM(18, 2)
        VFENCE()
        TEST_CHECK_EQ(x18, 300)

        // t4: VREDSUM again -- acc should reset btwn
        VREDSUM(19, 0)
        VFENCE()
        TEST_CHECK_EQ(x19, 10)

        VREDSUM(20, 1)
        VFENCE()
        TEST_CHECK_EQ(x20, 100)

        TEST_RISCV_END

        .data
        .align 4
src1:   .word 1, 2, 3, 4
src2:   .word 10, 20, 30, 40
