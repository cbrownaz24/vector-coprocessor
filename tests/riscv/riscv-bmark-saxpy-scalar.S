//=========================================================================
// riscv-bmark-saxpy-scalar.S - Scalar scale+add benchmark (16 elements)
//=========================================================================
// dest[i] = 5 * src[i] for i=0..15
// Pure scalar multiply benchmark

#include "riscv-macros.h"

        TEST_RISCV_BEGIN

        la    x10, src_data
        la    x11, dest_data
        li    x12, 5           // scalar multiplier
        li    x13, 16          // count

        // Stats on
        li    x1, 1
        csrw  10, x1
        nop; nop; nop; nop; nop

1:      lw    x14, 0(x10)
        mul   x15, x14, x12
        sw    x15, 0(x11)
        addi  x10, x10, 4
        addi  x11, x11, 4
        addi  x13, x13, -1
        bne   x13, x0, 1b

        // Stats off
        li    x1, 0
        csrw  10, x1
        nop; nop; nop; nop; nop

        // Verify
        la    x11, dest_data
        lw    x14, 0(x11)
        TEST_CHECK_EQ(x14, 50)        // 5*10
        lw    x14, 60(x11)            // dest[15]
        TEST_CHECK_EQ(x14, 800)       // 5*160

        TEST_RISCV_END

        .data
        .align 4
src_data:
        .word 10, 20, 30, 40, 50, 60, 70, 80
        .word 90, 100, 110, 120, 130, 140, 150, 160
dest_data:
        .space 64
