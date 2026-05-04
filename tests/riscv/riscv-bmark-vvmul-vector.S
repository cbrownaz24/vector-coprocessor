//=========================================================================
// riscv-bmark-vvmul-vector.S - Vector element-wise multiply (32 elements)
//=========================================================================
// dest[i] = a[i] * b[i] for i = 0..31

#include "riscv-macros.h"
#include "riscv-vec-macros.h"

        TEST_RISCV_BEGIN

        la    x10, a_data
        la    x11, b_data
        la    x12, dest_data
        li    x13, 32
        SETVL(14, 13)
        VFENCE()
        CVM()
        VFENCE()

        // Stats on
        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

        VLW(0, 10)              // v0 = a[0:31]
        VLW(1, 11)              // v1 = b[0:31]
        VVMUL(2, 0, 1)          // v2 = a * b (element-wise)
        VSW(2, 12)              // store dest
        VFENCE()

        // Stats off
        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        la    x12, dest_data
        lw    x14, 0(x12)
        TEST_CHECK_EQ(x14, 1)
        lw    x14, 124(x12)
        TEST_CHECK_EQ(x14, 1024)

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
dest_data:
        .space 128
