//========================================================================
// riscv-vec-macros.h - macros for vec coproc instrs
//========================================================================
// asm doesnt know our custom-0 vec instrs so we .word the raw 32-bit
// enconding ourselves.
//
// custom-0 opcode = 0x0B (0001011)
// R-type: funct7[31:25] | rs2[24:20] | rs1[19:15] | funct3[14:12] | rd[11:7] | opcode[6:0]

#ifndef RISCV_VEC_MACROS_H
#define RISCV_VEC_MACROS_H

// opcode for all vec instrs
#define VEC_OPCODE 0x0B

// funct3 categories
#define VV_ARITH 0x0
#define VS_ARITH 0x1
#define VMEM     0x2
#define VCONFIG  0x3
#define VCOMP    0x4
#define VREDUCE  0x5

// encode R-type custom-0 instr
// .word (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode
#define VEC_R_INST(funct7, rs2, rs1, funct3, rd) \
    .word ((funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | VEC_OPCODE)

//------------------------------------------------------------------------
// vec-vec arith (funct3 = 0x0)
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
// vec-scalar arith (funct3 = 0x1)
// rs2 field holds the scalar reg idx
//------------------------------------------------------------------------
#define VSADD(vd, vs1, rs2)   VEC_R_INST(0x00, rs2, vs1, VS_ARITH, vd)
#define VSSUB(vd, vs1, rs2)   VEC_R_INST(0x01, rs2, vs1, VS_ARITH, vd)
#define VSMUL(vd, vs1, rs2)   VEC_R_INST(0x02, rs2, vs1, VS_ARITH, vd)
#define VSDIV(vd, vs1, rs2)   VEC_R_INST(0x03, rs2, vs1, VS_ARITH, vd)
#define VSREM(vd, vs1, rs2)   VEC_R_INST(0x04, rs2, vs1, VS_ARITH, vd)

//------------------------------------------------------------------------
// vec mem (funct3 = 0x2)
// VLW: vd = load from M[x[rs1]]
// VSW: store vs1 to M[x[rs2]]  (rs1 field = vs1, rs2 field = base reg)
// VLWS: vd = strided load from M[x[rs1] + i*x[rs2]]
// VSWS: strided store vs1 to M[x[rs1] + i*x[rs2]]
//------------------------------------------------------------------------
#define VLW(vd, rs1)           VEC_R_INST(0x00, 0, rs1, VMEM, vd)
#define VSW(vs1, rs2)          VEC_R_INST(0x01, rs2, vs1, VMEM, 0)
#define VLWS(vd, rs1, rs2)     VEC_R_INST(0x02, rs2, rs1, VMEM, vd)
// VSWS encoding: rs1 slot = base_reg, rs2 slot = stride_reg, and vs1
// (the vec src reg) is encoded in the rd slot. CoreCtrl picks vs1 from
// rd[2:0] when funct3=VMEM && funct7=0x03.
#define VSWS(vs1, rs1, rs2)    VEC_R_INST(0x03, rs2, rs1, VMEM, vs1)

//------------------------------------------------------------------------
// vec cfg (funct3 = 0x3)
//------------------------------------------------------------------------
#define SETVL(rd, rs1)         VEC_R_INST(0x00, 0, rs1, VCONFIG, rd)
#define CVM()                  VEC_R_INST(0x01, 0, 0, VCONFIG, 0)
#define VFENCE()               VEC_R_INST(0x02, 0, 0, VCONFIG, 0)

//------------------------------------------------------------------------
// vec cmp (funct3 = 0x4) - sets mask reg
//------------------------------------------------------------------------
#define VSEQ(vs1, vs2)         VEC_R_INST(0x00, vs2, vs1, VCOMP, 0)
#define VSLT(vs1, vs2)         VEC_R_INST(0x01, vs2, vs1, VCOMP, 0)
#define VSLE(vs1, vs2)         VEC_R_INST(0x02, vs2, vs1, VCOMP, 0)
#define VSGT(vs1, vs2)         VEC_R_INST(0x03, vs2, vs1, VCOMP, 0)
#define VSGE(vs1, vs2)         VEC_R_INST(0x04, vs2, vs1, VCOMP, 0)
#define VSNE(vs1, vs2)         VEC_R_INST(0x05, vs2, vs1, VCOMP, 0)

//------------------------------------------------------------------------
// vec reduction (funct3 = 0x5) - result to scalar rd
//------------------------------------------------------------------------
#define VREDSUM(rd, vs1)       VEC_R_INST(0x00, 0, vs1, VREDUCE, rd)
#define VREDAND(rd, vs1)       VEC_R_INST(0x01, 0, vs1, VREDUCE, rd)
#define VREDOR(rd, vs1)        VEC_R_INST(0x02, 0, vs1, VREDUCE, rd)

#endif
