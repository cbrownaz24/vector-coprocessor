//========================================================================
// riscv-vec-macros.h - Macros for vector coprocessor instructions
//========================================================================
// Since the assembler doesn't know our custom-0 vector instructions,
// we use .word to emit raw 32-bit encodings.
//
// Custom-0 opcode = 0x0B (0001011)
// R-type format: funct7[31:25] | rs2[24:20] | rs1[19:15] | funct3[14:12] | rd[11:7] | opcode[6:0]

#ifndef RISCV_VEC_MACROS_H
#define RISCV_VEC_MACROS_H

// Opcode for all vector instructions
#define VEC_OPCODE 0x0B

// funct3 categories
#define VV_ARITH 0x0
#define VS_ARITH 0x1
#define VMEM     0x2
#define VCONFIG  0x3
#define VCOMP    0x4
#define VREDUCE  0x5

// Encode an R-type custom-0 instruction
// .word (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
#define VEC_R_INST(funct7, rs2, rs1, funct3, rd) \
    .word ((funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | VEC_OPCODE)

//------------------------------------------------------------------------
// Vector-Vector Arithmetic (funct3 = 0x0)
//------------------------------------------------------------------------
#define VVADD(vd, vs1, vs2)   VEC_R_INST(0x00, vs2, vs1, VV_ARITH, vd)
#define VVSUB(vd, vs1, vs2)   VEC_R_INST(0x01, vs2, vs1, VV_ARITH, vd)
#define VVMUL(vd, vs1, vs2)   VEC_R_INST(0x02, vs2, vs1, VV_ARITH, vd)
#define VVDIV(vd, vs1, vs2)   VEC_R_INST(0x03, vs2, vs1, VV_ARITH, vd)
#define VVREM(vd, vs1, vs2)   VEC_R_INST(0x04, vs2, vs1, VV_ARITH, vd)
#define VVAND(vd, vs1, vs2)   VEC_R_INST(0x05, vs2, vs1, VV_ARITH, vd)
#define VVOR(vd, vs1, vs2)    VEC_R_INST(0x06, vs2, vs1, VV_ARITH, vd)
#define VVXOR(vd, vs1, vs2)   VEC_R_INST(0x07, vs2, vs1, VV_ARITH, vd)
#define VVSLL(vd, vs1, vs2)   VEC_R_INST(0x08, vs2, vs1, VV_ARITH, vd)
#define VVSRL(vd, vs1, vs2)   VEC_R_INST(0x09, vs2, vs1, VV_ARITH, vd)
#define VVSRA(vd, vs1, vs2)   VEC_R_INST(0x0A, vs2, vs1, VV_ARITH, vd)

//------------------------------------------------------------------------
// Vector-Scalar Arithmetic (funct3 = 0x1)
// rs2 field holds the scalar register index
//------------------------------------------------------------------------
#define VSADD(vd, vs1, rs2)   VEC_R_INST(0x00, rs2, vs1, VS_ARITH, vd)
#define VSSUB(vd, vs1, rs2)   VEC_R_INST(0x01, rs2, vs1, VS_ARITH, vd)
#define VSMUL(vd, vs1, rs2)   VEC_R_INST(0x02, rs2, vs1, VS_ARITH, vd)
#define VSDIV(vd, vs1, rs2)   VEC_R_INST(0x03, rs2, vs1, VS_ARITH, vd)
#define VSREM(vd, vs1, rs2)   VEC_R_INST(0x04, rs2, vs1, VS_ARITH, vd)

//------------------------------------------------------------------------
// Vector Memory (funct3 = 0x2)
// VLW: vd = load from M[x[rs1]]
// VSW: store vs1 to M[x[rs2]]  (rs1 field = vs1, rs2 field = base reg)
// VLWS: vd = strided load from M[x[rs1] + i*x[rs2]]
// VSWS: strided store vs1 to M[x[rs1] + i*x[rs2]]
//------------------------------------------------------------------------
#define VLW(vd, rs1)           VEC_R_INST(0x00, 0, rs1, VMEM, vd)
#define VSW(vs1, rs2)          VEC_R_INST(0x01, rs2, vs1, VMEM, 0)
#define VLWS(vd, rs1, rs2)     VEC_R_INST(0x02, rs2, rs1, VMEM, vd)
#define VSWS(vs1, rs1, rs2)    VEC_R_INST(0x03, rs2, rs1, VMEM, 0)

//------------------------------------------------------------------------
// Vector Config (funct3 = 0x3)
//------------------------------------------------------------------------
#define SETVL(rd, rs1)         VEC_R_INST(0x00, 0, rs1, VCONFIG, rd)
#define CVM()                  VEC_R_INST(0x01, 0, 0, VCONFIG, 0)
#define VFENCE()               VEC_R_INST(0x02, 0, 0, VCONFIG, 0)

//------------------------------------------------------------------------
// Vector Comparison (funct3 = 0x4) - sets mask register
//------------------------------------------------------------------------
#define VSEQ(vs1, vs2)         VEC_R_INST(0x00, vs2, vs1, VCOMP, 0)
#define VSLT(vs1, vs2)         VEC_R_INST(0x01, vs2, vs1, VCOMP, 0)
#define VSLE(vs1, vs2)         VEC_R_INST(0x02, vs2, vs1, VCOMP, 0)
#define VSGT(vs1, vs2)         VEC_R_INST(0x03, vs2, vs1, VCOMP, 0)
#define VSGE(vs1, vs2)         VEC_R_INST(0x04, vs2, vs1, VCOMP, 0)
#define VSNE(vs1, vs2)         VEC_R_INST(0x05, vs2, vs1, VCOMP, 0)

//------------------------------------------------------------------------
// Vector Reduction (funct3 = 0x5) - result to scalar rd
//------------------------------------------------------------------------
#define VREDSUM(rd, vs1)       VEC_R_INST(0x00, 0, vs1, VREDUCE, rd)
#define VREDAND(rd, vs1)       VEC_R_INST(0x01, 0, vs1, VREDUCE, rd)
#define VREDOR(rd, vs1)        VEC_R_INST(0x02, 0, vs1, VREDUCE, rd)

#endif
