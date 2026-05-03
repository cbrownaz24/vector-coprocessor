//=========================================================================
// riscv-bmark-saxpy-vector.S - vec scale bench, 16 elems
//=========================================================================
// dest[i] = 5 * src[i] for i=0..15
// uses VSMUL

#include "riscv-macros.h"
#include "riscv-vec-macros.h"

        TEST_RISCV_BEGIN

        la    x10, src_data
        la    x11, dest_data
        li    x12, 5

        // vl=16
        li    x13, 16
        SETVL(14, 13)
        VFENCE()
        CVM()
        VFENCE()

        // stats on
        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

        VLW(0, 10)             // v0 = src[0:15]
        VSMUL(1, 0, 12)        // v1 = 5*v0
        VSW(1, 11)             // dest = v1
        VFENCE()

        // stats off
        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        // verfy
        la    x11, dest_data
        lw    x14, 0(x11)
        TEST_CHECK_EQ(x14, 50)
        lw    x14, 60(x11)
        TEST_CHECK_EQ(x14, 800)

        TEST_RISCV_END

        .data
        .align 4
src_data:
        .word 10, 20, 30, 40, 50, 60, 70, 80
        .word 90, 100, 110, 120, 130, 140, 150, 160
dest_data:
        .space 64
