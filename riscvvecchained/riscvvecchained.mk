#=========================================================================
# riscvvecchained Subpackage (chaining-branch RTL, no-dash subpkg name)
#=========================================================================

riscvvecchained_deps = \
  vc \
  imuldiv \

riscvvecchained_srcs = \
  riscvvec-CoreDpath.v \
  riscvvec-CoreDpathRegfile.v \
  riscvvec-CoreDpathAlu.v \
  riscvvec-CoreCtrl.v \
  riscvvec-Core.v \
  riscvvec-InstMsg.v \
  riscvvec-CoreDpathPipeMulDiv.v \
  riscvvec-VecRegfile.v \
  riscvvec-VecAlu.v \
  riscvvec-VecCmdQueue.v \
  riscvvec-VecCtrl.v \
  riscvvec-VecDpath.v \
  riscvvec-VecUnit.v \

riscvvecchained_test_srcs = \
  riscvvec-InstMsg.t.v \
  riscvvec-CoreDpathPipeMulDiv.t.v \

riscvvecchained_prog_srcs = \
  riscvvec-chained-sim.v \
  riscvvec-chained-randdelay-sim.v \
