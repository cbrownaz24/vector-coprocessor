//=========================================================================
// riscv-bmark-vvadd-vector.S - Vector VVADD benchmark (32 elements)
//=========================================================================
// dest[i] = src0[i] + src1[i] for i=0..31
// Uses vector coprocessor with SETVL=32 (one vector op covers all)

#include "riscv-macros.h"
#include "riscv-vec-macros.h"

        TEST_RISCV_BEGIN

        // Setup pointers
        la    x10, src0
        la    x11, src1
        la    x12, dest

        // Set VL=32
        li    x13, 32
        SETVL(14, 13)
        VFENCE()
        CVM()
        VFENCE()

        // Stats on
        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

        // Vector VVADD: 3 vector instructions instead of 32 loop iterations
        VLW(0, 10)             // v0 = src0[0:31]
        VLW(1, 11)             // v1 = src1[0:31]
        VVADD(2, 0, 1)         // v2 = v0 + v1
        VSW(2, 12)             // dest[0:31] = v2
        VFENCE()               // wait for completion

        // Stats off
        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        // Verify first and last elements
        la    x12, dest
        lw    x14, 0(x12)
        TEST_CHECK_EQ(x14, 11)        // 10+1=11
        lw    x14, 124(x12)           // dest[31]
        TEST_CHECK_EQ(x14, 352)       // 320+32=352

        TEST_RISCV_END

        .data
        .align 4
src0:
        .word 10, 20, 30, 40, 50, 60, 70, 80
        .word 90, 100, 110, 120, 130, 140, 150, 160
        .word 170, 180, 190, 200, 210, 220, 230, 240
        .word 250, 260, 270, 280, 290, 300, 310, 320
src1:
        .word 1, 2, 3, 4, 5, 6, 7, 8
        .word 9, 10, 11, 12, 13, 14, 15, 16
        .word 17, 18, 19, 20, 21, 22, 23, 24
        .word 25, 26, 27, 28, 29, 30, 31, 32
dest:
        .space 128
