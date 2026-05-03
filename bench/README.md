# Evaluation framework

Self-contained benchmarking and plotting for the vector-coprocessor
project. Lives entirely under `vector-coprocessor/`; the four baseline
processors (`riscvbyp`, `riscvlong`, `riscvooo`) and both vector
variants (`riscvvec`, `riscvvec-chained`) are all in-tree subpackages
that build through the same `build/Makefile`.

## Methodology

### Processors compared

| Name | Description | Vector? |
|---|---|---|
| **riscvbyp** | 5-stage pipeline with full bypassing, iterative integer multiply/divide. The course baseline. | no |
| **riscvlong** | Longer pipeline with fully pipelined integer mul/div (no muldiv stalls). Same ISA as byp. | no |
| **riscvooo** | Out-of-order dual-issue superscalar with scoreboard and ROB. | no |
| **riscvvec** | 5-stage scalar pipeline + decoupled vector coprocessor (master design): 33 instructions, 8 vector regs of 32 elements, command queue. | yes |
| **riscvvec-chained** | riscvvec plus Cray-style producer/consumer chaining of arithmetic ops. Two ALU instances, three regfile read ports, two write ports, dual-issue VecCtrl. | yes |

`riscvbyp` is the baseline for speedup ratios. `riscvlong` and
`riscvooo` are the "what if you tried more ILP without explicit
vectors" comparison points. `riscvstall` and `riscvssc` from the same
A3 distribution are excluded — degraded baselines and dual-fetch
front-ends are orthogonal to the vector-vs-scalar question.

### Benchmarks

| Name | Description | Vector form | Why it's here |
|---|---|---|---|
| **vvadd**   | 32-element element-wise add | `riscv-bmark-vvadd-vector.S` | Memory-bound limit case |
| **saxpy**   | 16-element scale `y = a*x` | `riscv-bmark-saxpy-vector.S` | Single-multiply-per-element compute |
| **daxpy**   | 32-element `y = a*x + y` | `riscv-bmark-daxpy-vector.S` | Has a chainable `VSMUL → VVADD` pair |
| **linpack** | 16x16 matrix-vector multiply | `riscv-bmark-linpack-vector-16x16.S` | Real LINPACK-style dense linear algebra kernel |
| **ubmark-vvadd, -cmplx-mult, -bin-search, -masked-filter** | C-language benchmarks from the course test suite | (scalar only) | Establishes scalar-baseline parity across processor variants |

Plus three sweep families (real, measured, no analytical predictions):

- `daxpy_n` — DAXPY at N ∈ {16, 32, 64, 128, 256}, strip-mined for VL > 32
- `linpack_size` — LINPACK at NxN ∈ {4, 8, 16, 32}
- `sweep_queue` — `VEC_CMD_QUEUE_DEPTH` ∈ {2, 4, 8, 16}, run on a
  pipelined-LINPACK variant that intentionally does not VFENCE between
  rows (so the queue can actually fill)

### Energy model

`energy_model.py` decomposes each run into four components:

```
E_total = E_overhead  + E_compute  + E_memory   + E_idle
        = e_fd*insts  + e_op*ops   + e_mem*acc  + e_idle*cycles
```

`insts` and `cycles` are measured by the simulator. `ops` and `acc`
come from a workload profile (a property of the algorithm, not the
processor). The model directly exposes the H&P Ch. 4 prediction:
vector mode reduces `insts` by 5–12x, leaving `ops`, `acc`, and (most
of) `cycles` similar — so `E_overhead` shrinks dramatically while the
other components stay roughly constant.

The constants are pedagogical (rough 28nm CMOS ratios, not synthesis-
calibrated). **Read ratios, not absolutes.** To calibrate: drive
Synopsys DC compile with .saif/.vcd from the existing `+vcd=1` flag,
extract per-cycle and per-event energies, replace the four constants
in `energy_model.py`. The decomposition stays the same.

## Usage

```bash
# 1. Make sure all five sims are built
cd ../build
source /home/ECE475/env_spr2026.sh    # course toolchain
for sim in riscvbyp-sim riscvlong-sim riscvooo-sim \
           riscvvec-sim riscvvec-chained-sim; do
    make $sim
done

# 2. (Optional) regenerate scaling .S files
cd ../bench
python3 gen_scaling_benchmarks.py
cd ../tests/build && make all && ../convert
cd ../../bench

# 3. Run all (processor, benchmark, mode) combinations
python3 run_bench.py                 # writes results/main.csv,
                                     # results/daxpy_n.csv,
                                     # results/linpack_size.csv

# 4. Run the queue-depth sweep
python3 sweep_bench.py               # writes results/sweep_queue.csv

# 5. Render all eight figures
python3 make_plots.py                # writes plots/fig1_*.png ... fig8_*.png
```

## Files

| File | Purpose |
|---|---|
| `benchmarks.json` | Benchmark catalog with vmh names, sizes, and grouping. |
| `processors.json` | Processor catalog with sim binary paths and plot colors. |
| `run_bench.py` | Run every (proc, bench, mode); emit main + scaling CSVs. |
| `sweep_bench.py` | Rebuild the vector sim at each `VEC_CMD_QUEUE_DEPTH` and run all vector benchmarks. |
| `gen_scaling_benchmarks.py` | Generate parameterized DAXPY-N, LINPACK-NxN, and pipelined-LINPACK .S files. |
| `energy_model.py` | Instruction-amortized analytical energy model. |
| `plot_lib.py` | Shared matplotlib styling and CSV loader. |
| `make_plots.py` | Eight-figure plot suite (one function per figure). |
| `results/*.csv` | Saved measurements, ready to import. |
| `plots/*.png` | Rendered figures. |

## What each figure answers

1. **`fig1_cycles_per_kernel.png`** — How does each processor variant
   handle each kernel? Four panels with independent y-axes so the
   smaller kernels aren't drowned out by LINPACK.
2. **`fig2_speedup_over_baseline.png`** — How much does each design
   win over the riscvbyp scalar baseline, per kernel? Speedup labels
   above bars; horizontal line at 1x.
3. **`fig3_daxpy_scaling.png`** — Does the vector advantage grow with
   problem size? Log-log lines, one per processor.
4. **`fig4_linpack_scaling.png`** — Same question for dense linear
   algebra; the gap between scalar and vector grows with N because
   fixed overhead amortizes.
5. **`fig5_instruction_count.png`** — Direct evidence of the
   fetch/decode amortization: scalar retires 7–12x more dynamic
   instructions than vector for the same workload.
6. **`fig6_energy_breakdown.png`** — Stacked-bar breakdown of energy
   into overhead/compute/memory/idle components, per kernel. Shows
   the **overhead** stripe (driven by instruction count) shrinks
   dramatically in vector mode while compute, memory, and idle stay
   comparable.
7. **`fig7_edp.png`** — Energy-Delay Product across all five
   processors. Lower is better. Vector designs win on every kernel;
   chaining is a small additional win on DAXPY.
8. **`fig8_queue_depth.png`** — Cycle count vs `VEC_CMD_QUEUE_DEPTH`
   ∈ {2, 4, 8, 16}. Flat for both standard kernels (each VFENCE
   drains the queue) and pipelined-LINPACK (vector unit is the
   bottleneck, scalar dispatch never stalls). A real, measured
   negative result: queue depth is not a performance lever for these
   workloads.

## Adding a new benchmark

1. Add `riscv-bmark-<name>-{scalar,vector}.S` to `tests/riscv/`.
2. Add to `tests/riscv/riscv.mk`.
3. Add the `.vmh` to the `tests` list in `build/Makefile`.
4. From `tests/build/`: `source ...env_spr2026.sh; make all && ../convert`.
5. Add an entry to `benchmarks.json`. Update `energy_model.PROFILES`
   if you want the energy plot to show it correctly.

## Adding a new processor

1. Drop the source directory under `vector-coprocessor/`.
2. Add to `subpkgs` in `build/Makefile` — note: subpkg names with
   dashes break the in-tree subpkg-template's `-I` path; use
   underscore-free names (e.g., `riscvvecchained`, not
   `riscvvec-chained`).
3. Add an entry to `processors.json` with `is_vector_capable` set
   appropriately.
4. Re-run `run_bench.py`.

## Bugs found during framework development

While bringing tests on line, the new framework exposed three
pre-existing latent bugs in the master design. All three were caught
because the new tests covered code paths the original 13-test suite
did not exercise:

1. **VREDSUM off-by-one** (`riscvvec-VecCtrl.v`) — the final
   accumulator update is registered, but `reduce_val` was asserted on
   the same cycle, publishing the value *before* the last element
   was added. Fixed by computing the final result combinationally
   on the publication cycle.
2. **VSWS missing vector-source encoding** (`riscv-vec-macros.h` and
   `riscvvec-CoreCtrl.v`) — the VSWS macro silently dropped the
   `vs1` argument because the instruction format had no slot left;
   strided stores ran with `vs1` = base-address-register-index
   (e.g., loading from vreg #12 when only 8 exist). Fixed by
   encoding `vs1` in the rd field and adding a CoreCtrl override.
3. **SETVL clamp tested only the low 6 bits** (`riscvvec-VecCtrl.v`)
   — requests of N=64..95 wrapped to 0..31 silently. Fixed by
   comparing the full 32-bit operand against 32.

All three fixes are in the chaining branch's copies as well so cross-
branch behaviour is consistent.
