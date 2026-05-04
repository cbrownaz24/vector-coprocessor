//=========================================================================
// riscv-bmark-daxpy-vector.S - vec daxpy bench, 32 elems
//=========================================================================
// y[i] = a*x[i] + y[i] for i=0..31
// uses vec coproc: VSMUL + VVADD

#include "riscv-macros.h"
#include "riscv-vec-macros.h"

        TEST_RISCV_BEGIN

        la    x10, x_data
        la    x11, y_data
        li    x12, 3           // scalar a=3

        // vl=32
        li    x13, 32
        SETVL(14, 13)
        VFENCE()
        CVM()
        VFENCE()

        // stats on
        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

        // vec daxpy
        VLW(0, 10)             // v0 = x[0:31]
        VLW(1, 11)             // v1 = y[0:31]
        VSMUL(2, 0, 12)        // v2 = a*v0
        VVADD(3, 2, 1)         // v3 = v2+v1 = a*x+y
        VSW(3, 11)             // y[0:31] = v3
        VFENCE()

        // stats off
        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        // verify
        la    x11, y_data
        lw    x14, 0(x11)
        TEST_CHECK_EQ(x14, 103)       // 3*1 + 100
        lw    x14, 124(x11)
        TEST_CHECK_EQ(x14, 227)       // 3*32 + 131

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
