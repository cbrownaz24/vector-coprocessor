"""
energy_model.py - instr-amortized energy model

splits per-run energy into 4 parts, each driven by a measurable from
sim + known benchmark profile:

    E_total = E_overhead + E_compute + E_memory + E_idle

  E_overhead = e_fd  * num_inst       # fetch + decode + dispatch
  E_compute  = e_op  * num_ops        # alu ops actually done
  E_memory   = e_mem * num_mem        # mem accesses
  E_idle     = e_idle * num_cycles    # clk + leakage

this exposes the H&P ch4 claim: a vec program does the same num_ops
and num_mem as its scalar twin, but runs way fewer num_inst since each
vec instr is a whole loop body. so fetch/decode oerhead amortizes away.

constants are arb units, ratios picked from textbook 28nm cmos rules of
thumb (regfile read >> alu, sram >> reg access by ~10x, muldiv stall
bumps per-inst avg). NOT calibrated to synth. plots ok for relative
compare across configs, absolutes not meaningful.

cal path: synopsys DC w/ .saif/.vcd traces, read per-cycle + per-event
nrg, swap these consts. decomposition stays same.
"""

from __future__ import annotations

from dataclasses import dataclass


# nrg coefs - arb units, rough textbook ratios
E_FETCH_DECODE = 22.0   # per dyn instr (fetch + decode + rf read)
E_ALU_OP       = 6.0    # per alu op
E_MEM_ACCESS   = 30.0   # per mem ld/st
E_IDLE_CYCLE   = 8.0    # per clk cycle (background)

# vec unit premiums
E_VEC_DISPATCH_BONUS = 4.0   # extra per vec instr (queue + decoee in vec unit)
E_VEC_OP_BONUS       = 2.0   # extra per vec alu elem (multi-port rf, mask gate)


@dataclass
class BenchmarkProfile:
    """how many ops + mem accesses a benchmark does. proc-independent,
    its just a property of the workload."""
    name: str
    num_ops: int        # arith ops (mul, add, etc)
    num_mem: int        # mem ld + st
    description: str = ""


# workload profiles - actual compute each bench does, regardless of code
# (scalar loop vs vec strip)
PROFILES: dict[str, BenchmarkProfile] = {
    "vvadd":   BenchmarkProfile("vvadd",   num_ops=32,  num_mem=32*3,
                                description="32-elem add: 32 adds, 64 lds + 32 sts"),
    "saxpy":   BenchmarkProfile("saxpy",   num_ops=16,  num_mem=16*2,
                                description="16-elem scale: 16 muls, 16 lds + 16 sts"),
    "daxpy":   BenchmarkProfile("daxpy",   num_ops=32*2, num_mem=32*3,
                                description="32-elem a*x+y: 32 muls + 32 adds, 64 lds + 32 sts"),
    "linpack": BenchmarkProfile("linpack", num_ops=16*16*2, num_mem=16*16+16*1+16,
                                description="16x16 matvec: 256 muls + 256 adds, A lds + x lds + y sts"),
}

# parameterized profiles for scaling sweeps
def daxpy_profile(n: int) -> BenchmarkProfile:
    return BenchmarkProfile(f"daxpy-N{n}", num_ops=2*n, num_mem=3*n,
                            description=f"daxpy N={n}: {2*n} muls+adds, {3*n} mem")

def linpack_profile(n: int) -> BenchmarkProfile:
    # NxN matvec: N*N muls + N*N adds, N*N + N + N mem accesses
    return BenchmarkProfile(f"linpack-{n}x{n}", num_ops=2*n*n, num_mem=n*n + 2*n,
                            description=f"linpack {n}x{n}: {2*n*n} ops, {n*n+2*n} mem")


@dataclass
class EnergyBreakdown:
    overhead: float    # fetch + decode
    compute:  float    # alu work
    memory:   float    # mem accesses
    idle:     float    # background clk
    total:    float

    def as_dict(self) -> dict[str, float]:
        return {"overhead": self.overhead, "compute": self.compute,
                "memory": self.memory, "idle": self.idle, "total": self.total}


def estimate_energy(
    *,
    cycles: int,
    instructions: int,
    profile: BenchmarkProfile,
    is_vector_mode: bool = False,
    num_vec_dispatches: int | None = None,
) -> EnergyBreakdown:
    """compute decomposed nrg in arb units.

    `instructions` is sim's num_inst (decoded instrs from scalar pipe).
    in vec mode this includes the small # of vec dispatches.
    `num_vec_dispatches` lets caller tag part of `instructions` as vec
    dispatches to get the per-dispatch premium. None = skip premium.
    """
    overhead = E_FETCH_DECODE * instructions
    if is_vector_mode and num_vec_dispatches:
        overhead += E_VEC_DISPATCH_BONUS * num_vec_dispatches

    compute = E_ALU_OP * profile.num_ops
    if is_vector_mode:
        compute += E_VEC_OP_BONUS * profile.num_ops

    memory = E_MEM_ACCESS * profile.num_mem
    idle = E_IDLE_CYCLE * cycles

    total = overhead + compute + memory + idle
    return EnergyBreakdown(overhead=overhead, compute=compute,
                           memory=memory, idle=idle, total=total)


def lookup_profile(benchmark_name: str) -> BenchmarkProfile | None:
    """resolve a bench name (eg 'daxpy-N64' or 'linpack-32x32') to a
    profile, incl the parameterized scaling sweeps."""
    if benchmark_name in PROFILES:
        return PROFILES[benchmark_name]
    if benchmark_name.startswith("daxpy-N"):
        try:
            return daxpy_profile(int(benchmark_name.split("N")[-1]))
        except ValueError:
            return None
    if benchmark_name.startswith("linpack-") and "x" in benchmark_name:
        try:
            n = int(benchmark_name.split("-")[1].split("x")[0])
            return linpack_profile(n)
        except ValueError:
            return None
    return None
