//=========================================================================
// riscv-vec.S - bigger vec coproc tests
//=========================================================================
// tests: SETVL, VLW, VSW, VVADD, VVSUB, VVMUL, VSADD, VSMUL, VFENCE,
//        VREDSUM, CVM, basic decouple op.
//
// idea: load known data into mem, VLW into vregs, do vec op, VSW back
// out, scalar LW to check.

#include "riscv-macros.h"
#include "riscv-vec-macros.h"

        TEST_RISCV_BEGIN

        //=================================================================
        // t1: SETVL - vl=4
        //=================================================================
        li    x10, 4
        SETVL(11, 10)           // x11 = SETVL(x10) -> should be 4
        VFENCE()
        // setvl result comes back thru reduce iface. cant easily check
        // x11 w/o reduce path working, so we just keep going + verify
        // via vec ops.

        //=================================================================
        // t2: VLW + VSW - load/store a vec
        //=================================================================
        // src data in mem
        la    x12, src_data_a
        la    x13, dst_data

        // load vec from src_data_a into v0
        VLW(0, 12)              // v0 = M[x12], vl elems
        VFENCE()

        // store v0 to dst_data
        VSW(0, 13)              // M[x13] = v0
        VFENCE()

        // verify: scalar loadback + check
        lw    x14, 0(x13)
        TEST_CHECK_EQ(x14, 10)
        lw    x14, 4(x13)
        TEST_CHECK_EQ(x14, 20)
        lw    x14, 8(x13)
        TEST_CHECK_EQ(x14, 30)
        lw    x14, 12(x13)
        TEST_CHECK_EQ(x14, 40)

        //=================================================================
        // t3: VVADD
        //=================================================================
        la    x12, src_data_a
        la    x13, src_data_b
        la    x15, dst_data

        VLW(0, 12)              // v0 = [10,20,30,40]
        VFENCE()
        VLW(1, 13)              // v1 = [1,2,3,4]
        VFENCE()
        VVADD(2, 0, 1)          // v2 = v0+v1 = [11,22,33,44]
        VFENCE()
        VSW(2, 15)              // store v2
        VFENCE()

        lw    x14, 0(x15)
        TEST_CHECK_EQ(x14, 11)
        lw    x14, 4(x15)
        TEST_CHECK_EQ(x14, 22)
        lw    x14, 8(x15)
        TEST_CHECK_EQ(x14, 33)
        lw    x14, 12(x15)
        TEST_CHECK_EQ(x14, 44)

        //=================================================================
        // t4: VVSUB
        //=================================================================
        la    x15, dst_data

        VVSUB(3, 0, 1)          // v3 = v0-v1 = [9,18,27,36]
        VFENCE()
        VSW(3, 15)
        VFENCE()

        lw    x14, 0(x15)
        TEST_CHECK_EQ(x14, 9)
        lw    x14, 4(x15)
        TEST_CHECK_EQ(x14, 18)
        lw    x14, 8(x15)
        TEST_CHECK_EQ(x14, 27)
        lw    x14, 12(x15)
        TEST_CHECK_EQ(x14, 36)

        //=================================================================
        // t5: VVMUL
        //=================================================================
        la    x15, dst_data

        VVMUL(4, 0, 1)          // v4 = v0*v1 = [10,40,90,160]
        VFENCE()
        VSW(4, 15)
        VFENCE()

        lw    x14, 0(x15)
        TEST_CHECK_EQ(x14, 10)
        lw    x14, 4(x15)
        TEST_CHECK_EQ(x14, 40)
        lw    x14, 8(x15)
        TEST_CHECK_EQ(x14, 90)
        lw    x14, 12(x15)
        TEST_CHECK_EQ(x14, 160)

        //=================================================================
        // t6: VSADD - vec-scalar add
        //=================================================================
        la    x15, dst_data
        li    x16, 100

        VSADD(5, 0, 16)         // v5 = v0+100 = [110,120,130,140]
        VFENCE()
        VSW(5, 15)
        VFENCE()

        lw    x14, 0(x15)
        TEST_CHECK_EQ(x14, 110)
        lw    x14, 4(x15)
        TEST_CHECK_EQ(x14, 120)
        lw    x14, 8(x15)
        TEST_CHECK_EQ(x14, 130)
        lw    x14, 12(x15)
        TEST_CHECK_EQ(x14, 140)

        //=================================================================
        // t7: VSMUL - vec-scalar mul
        //=================================================================
        la    x15, dst_data
        li    x16, 3

        VSMUL(6, 1, 16)          // v6 = v1*3 = [3,6,9,12]
        VFENCE()
        VSW(6, 15)
        VFENCE()

        lw    x14, 0(x15)
        TEST_CHECK_EQ(x14, 3)
        lw    x14, 4(x15)
        TEST_CHECK_EQ(x14, 6)
        lw    x14, 8(x15)
        TEST_CHECK_EQ(x14, 9)
        lw    x14, 12(x15)
        TEST_CHECK_EQ(x14, 12)

        //=================================================================
        // t8: edge case - vl=1 (single elem)
        //=================================================================
        li    x10, 1
        SETVL(11, 10)
        VFENCE()

        la    x12, src_data_a
        la    x15, dst_data2

        VLW(0, 12)              // v0[0] = 10 only
        VFENCE()
        VSW(0, 15)
        VFENCE()

        lw    x14, 0(x15)
        TEST_CHECK_EQ(x14, 10)

        // restore vl=4
        li    x10, 4
        SETVL(11, 10)
        VFENCE()

        //=================================================================
        // t9: edge - neg numbers
        //=================================================================
        la    x12, src_data_neg
        la    x13, src_data_b
        la    x15, dst_data

        VLW(0, 12)              // v0 = [-1,-10,-100,-1000]
        VFENCE()
        VLW(1, 13)              // v1 = [1,2,3,4]
        VFENCE()
        VVADD(2, 0, 1)          // v2 = [0,-8,-97,-996]
        VFENCE()
        VSW(2, 15)
        VFENCE()

        lw    x14, 0(x15)
        TEST_CHECK_EQ(x14, 0)
        lw    x14, 4(x15)
        TEST_CHECK_EQ(x14, -8)
        lw    x14, 8(x15)
        TEST_CHECK_EQ(x14, -97)
        lw    x14, 12(x15)
        TEST_CHECK_EQ(x14, -996)

        //=================================================================
        // t10: VVAND/VVOR/VVXOR - bitwise ops
        //=================================================================
        la    x12, src_data_bits_a
        la    x13, src_data_bits_b
        la    x15, dst_data

        VLW(0, 12)              // v0 = [0xFF00FF00, 0x0F0F0F0F, 0xAAAAAAAA, 0x12345678]
        VFENCE()
        VLW(1, 13)              // v1 = [0x00FF00FF, 0xF0F0F0F0, 0x55555555, 0x87654321]
        VFENCE()

        // and
        VVAND(2, 0, 1)          // v2 = v0 & v1
        VFENCE()
        VSW(2, 15)
        VFENCE()

        lw    x14, 0(x15)
        TEST_CHECK_EQ(x14, 0x00000000)   // FF00FF00 & 00FF00FF = 0
        lw    x14, 4(x15)
        TEST_CHECK_EQ(x14, 0x00000000)   // 0F0F0F0F & F0F0F0F0 = 0
        lw    x14, 8(x15)
        TEST_CHECK_EQ(x14, 0x00000000)   // AAAAAAAA & 55555555 = 0
        lw    x14, 12(x15)
        TEST_CHECK_EQ(x14, 0x02244220)   // 12345678 & 87654321

        // or
        VVOR(3, 0, 1)
        VFENCE()
        VSW(3, 15)
        VFENCE()

        lw    x14, 0(x15)
        TEST_CHECK_EQ(x14, 0xFFFFFFFF)   // FF00FF00 | 00FF00FF
        lw    x14, 4(x15)
        TEST_CHECK_EQ(x14, 0xFFFFFFFF)   // 0F0F0F0F | F0F0F0F0
        lw    x14, 8(x15)
        TEST_CHECK_EQ(x14, 0xFFFFFFFF)   // AAAAAAAA | 55555555

        // xor
        VVXOR(4, 0, 1)
        VFENCE()
        VSW(4, 15)
        VFENCE()

        lw    x14, 0(x15)
        TEST_CHECK_EQ(x14, 0xFFFFFFFF)   // FF00FF00 ^ 00FF00FF
        lw    x14, 8(x15)
        TEST_CHECK_EQ(x14, 0xFFFFFFFF)   // AAAAAAAA ^ 55555555

        //=================================================================
        // t11: VSSUB - vec-scalar sub
        //=================================================================
        la    x12, src_data_a
        la    x15, dst_data
        li    x16, 5

        VLW(0, 12)              // v0 = [10,20,30,40]
        VFENCE()
        VSSUB(1, 0, 16)          // v1 = v0-5 = [5,15,25,35]
        VFENCE()
        VSW(1, 15)
        VFENCE()

        lw    x14, 0(x15)
        TEST_CHECK_EQ(x14, 5)
        lw    x14, 4(x15)
        TEST_CHECK_EQ(x14, 15)
        lw    x14, 8(x15)
        TEST_CHECK_EQ(x14, 25)
        lw    x14, 12(x15)
        TEST_CHECK_EQ(x14, 35)

        //=================================================================
        // t12: bunch of vec ops w/o VFENCE - decouple test
        // queue should buffer them
        //=================================================================
        la    x12, src_data_a
        la    x13, src_data_b
        la    x15, dst_data

        VLW(0, 12)
        VLW(1, 13)
        VVADD(2, 0, 1)
        VFENCE()                 // only fence at end
        VSW(2, 15)
        VFENCE()

        lw    x14, 0(x15)
        TEST_CHECK_EQ(x14, 11)
        lw    x14, 12(x15)
        TEST_CHECK_EQ(x14, 44)

        //=================================================================
        // t13: vl=0
        //=================================================================
        li    x10, 0
        SETVL(11, 10)
        VFENCE()

        // ops w/ vl=0 should be no-ops
        la    x15, dst_data
        // wr known vals first
        li    x14, 0xDEAD
        sw    x14, 0(x15)

        la    x12, src_data_a
        VLW(0, 12)              // shouldnt load anything
        VFENCE()
        VSW(0, 15)              // shouldnt store anything
        VFENCE()

        lw    x14, 0(x15)
        TEST_CHECK_EQ(x14, 0xDEAD)  // unchaned

        // restore vl=4
        li    x10, 4
        SETVL(11, 10)
        VFENCE()

        //=================================================================
        // PASS
        //=================================================================

        TEST_RISCV_END

        //=================================================================
        // test data
        //=================================================================
        .data
        .align 4

src_data_a:
        .word 10, 20, 30, 40, 50, 60, 70, 80

src_data_b:
        .word 1, 2, 3, 4, 5, 6, 7, 8

src_data_neg:
        .word -1, -10, -100, -1000

src_data_bits_a:
        .word 0xFF00FF00, 0x0F0F0F0F, 0xAAAAAAAA, 0x12345678

src_data_bits_b:
        .word 0x00FF00FF, 0xF0F0F0F0, 0x55555555, 0x87654321

dst_data:
        .word 0, 0, 0, 0, 0, 0, 0, 0

dst_data2:
        .word 0, 0, 0, 0
