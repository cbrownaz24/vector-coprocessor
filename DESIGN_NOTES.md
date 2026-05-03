# ECE 475 Vector Coprocessor - Design Notes
## Max Machado & Connor Brown | Spring 2026

---

## 1. Project Overview

We are extending the `riscvbyp` (5-stage bypassing pipeline) RISC-V processor with a
**decoupled vector coprocessor**. The coprocessor communicates with the scalar core via
a val-rdy handshake interface and has its own vector register file, SIMD ALU lanes,
vector mask register, and a command queue.

### Why `riscvbyp` as the base processor?

- **Full bypassing** provides good baseline scalar performance for fair comparison
- Supports **full RV32IM ISA** (arithmetic, logic, shifts, mul, div, rem, branches, loads/stores)
- **Clean ctrl/dpath separation** -- same pattern we replicate in the vector unit
- Complex enough to be realistic, simple enough to modify confidently
- `riscvstall` too slow (stalls on all hazards), `riscvlong` adds pipeline depth without
  new capability, `riscvdualfetch` adds frontend complexity orthogonal to our goal,
  `riscvooo` is reserved as a stretch goal

### Key Design Decision: Decoupled Coprocessor

Rather than extending the main pipeline with vector stages (tightly coupled), we use a
**decoupled architecture** where:
- The scalar core dispatches vector commands into a **command queue**
- The vector unit processes commands independently
- The scalar core only stalls on **VFENCE** (explicit synchronization) or when the
  command queue is full
- This allows the scalar core to continue useful work while vector operations execute

This mirrors real-world designs (e.g., Hwacha vector accelerator from UC Berkeley,
early Cray vector machines with separate scalar/vector units).

---

## 2. Vector ISA Specification

### 2.1 Instruction Encoding

We use RISC-V's **custom-0 opcode (0x0B)** for all vector instructions.
The 32-bit instruction format:

```
[31:25]  [24:20]  [19:15]  [14:12]  [11:7]   [6:0]
funct7   vs2/rs2  vs1/rs1  funct3   vd/rd    opcode(0x0B)
```

- `funct3` selects the instruction **category**
- `funct7` selects the specific **operation** within that category
- `vd` (bits 11:7) = destination vector register (3-bit used, 5-bit field)
- `vs1` (bits 19:15) = source vector register 1 or scalar register
- `vs2` (bits 24:20) = source vector register 2 or scalar register

### 2.2 Instruction Categories (funct3 encoding)

| funct3 | Category | Description |
|--------|----------|-------------|
| 3'b000 | VV_ARITH | Vector-vector arithmetic |
| 3'b001 | VS_ARITH | Vector-scalar arithmetic |
| 3'b010 | VMEM     | Vector memory (load/store) |
| 3'b011 | VCONFIG  | Configuration (SETVL, CVM, VFENCE) |
| 3'b100 | VCOMP    | Vector comparison (mask-setting) |
| 3'b101 | VREDUCE  | Reduction operations |
| 3'b110 | (reserved) | For future expansion |
| 3'b111 | (reserved) | For future expansion |

### 2.3 Full Instruction Table

#### Vector-Vector Arithmetic (funct3 = 3'b000)

| Instruction | funct7    | Operation | Description |
|-------------|-----------|-----------|-------------|
| VVADD       | 7'b0000000 | vd = vs1 + vs2 | Element-wise add |
| VVSUB       | 7'b0000001 | vd = vs1 - vs2 | Element-wise subtract |
| VVMUL       | 7'b0000010 | vd = vs1 * vs2 | Element-wise multiply |
| VVDIV       | 7'b0000011 | vd = vs1 / vs2 | Element-wise signed divide |
| VVREM       | 7'b0000100 | vd = vs1 % vs2 | Element-wise signed remainder |
| VVAND       | 7'b0000101 | vd = vs1 & vs2 | Element-wise bitwise AND |
| VVOR        | 7'b0000110 | vd = vs1 | vs2 | Element-wise bitwise OR |
| VVXOR       | 7'b0000111 | vd = vs1 ^ vs2 | Element-wise bitwise XOR |
| VVSLL       | 7'b0001000 | vd = vs1 << vs2 | Element-wise shift left |
| VVSRL       | 7'b0001001 | vd = vs1 >> vs2 | Element-wise logical shift right |
| VVSRA       | 7'b0001010 | vd = vs1 >>> vs2 | Element-wise arithmetic shift right |

#### Vector-Scalar Arithmetic (funct3 = 3'b001)

| Instruction | funct7    | Operation | Description |
|-------------|-----------|-----------|-------------|
| VSADD       | 7'b0000000 | vd[i] = vs1[i] + x[rs2] | Add scalar to each element |
| VSSUB       | 7'b0000001 | vd[i] = vs1[i] - x[rs2] | Subtract scalar from each element |
| VSMUL       | 7'b0000010 | vd[i] = vs1[i] * x[rs2] | Multiply each element by scalar |
| VSDIV       | 7'b0000011 | vd[i] = vs1[i] / x[rs2] | Divide each element by scalar |
| VSREM       | 7'b0000100 | vd[i] = vs1[i] % x[rs2] | Remainder of each element by scalar |

#### Vector Memory (funct3 = 3'b010)

| Instruction | funct7    | Operands | Description |
|-------------|-----------|----------|-------------|
| VLW         | 7'b0000000 | vd, rs1 | Load VL words from M[x[rs1]] into vd |
| VSW         | 7'b0000001 | vs1, rs2(base) | Store VL words from vs1 to M[x[rs2]] |
| VLWS        | 7'b0000010 | vd, rs1(base), rs2(stride) | Strided load: vd[i] = M[x[rs1] + i*x[rs2]] |
| VSWS        | 7'b0000011 | vs1, rs1(base), rs2(stride) | Strided store: M[x[rs1] + i*x[rs2]] = vs1[i] |

#### Configuration & Sync (funct3 = 3'b011)

| Instruction | funct7    | Operands | Description |
|-------------|-----------|----------|-------------|
| SETVL       | 7'b0000000 | rd, rs1 | VL = min(x[rs1], VLMAX); x[rd] = VL |
| CVM         | 7'b0000001 | (none) | Set all mask bits to 1 |
| VFENCE      | 7'b0000010 | (none) | Stall scalar core until vector unit idle |

#### Vector Comparison / Mask (funct3 = 3'b100)

| Instruction | funct7    | Operation | Description |
|-------------|-----------|-----------|-------------|
| VSEQ        | 7'b0000000 | VM[i] = (vs1[i] == vs2[i]) | Set mask if equal |
| VSLT        | 7'b0000001 | VM[i] = (vs1[i] < vs2[i])  | Set mask if less than |
| VSLE        | 7'b0000010 | VM[i] = (vs1[i] <= vs2[i]) | Set mask if less or equal |
| VSGT        | 7'b0000011 | VM[i] = (vs1[i] > vs2[i])  | Set mask if greater |
| VSGE        | 7'b0000100 | VM[i] = (vs1[i] >= vs2[i]) | Set mask if greater or equal |
| VSNE        | 7'b0000101 | VM[i] = (vs1[i] != vs2[i]) | Set mask if not equal |

#### Reduction (funct3 = 3'b101)

| Instruction | funct7    | Operation | Description |
|-------------|-----------|-----------|-------------|
| VREDSUM     | 7'b0000000 | x[rd] = sum(vs1[0:VL-1]) | Sum reduction to scalar |
| VREDAND     | 7'b0000001 | x[rd] = AND(vs1[0:VL-1]) | AND reduction to scalar |
| VREDOR      | 7'b0000010 | x[rd] = OR(vs1[0:VL-1])  | OR reduction to scalar |

**Total: 33 vector instructions**

---

## 3. Microarchitecture

### 3.1 Top-Level Block Diagram

```
  +------------------+       val/rdy cmd queue      +-------------------+
  |   Scalar Core    |------------------------------>|  Vector Unit      |
  |   (riscvbyp)     |<--------- done/result -------|                   |
  |                  |                               | +---------------+ |
  |  [fetch]         |                               | | VecCtrl (FSM) | |
  |  [decode]-----+  |                               | +-------+-------+ |
  |  [execute]    |  |                               |         |         |
  |  [memory]     |  |                               | +-------v-------+ |
  |  [writeback]  |  |                               | | VecDpath      | |
  |               |  |                               | | - VecRegfile  | |
  +---------------+--+                               | | - VecALU(x4) | |
         |    |                                       | | - MaskReg    | |
         v    v                                       | +-------+-------+ |
  +------+----+------+                               |         |         |
  |   Data Memory     |<---------- mem req/resp -----|         |         |
  |   (shared port)   |------------------------------>|         |         |
  +-------------------+                               +-------------------+
```

### 3.2 Vector Register File

- **8 vector registers** (v0-v7), addressed with 3 bits
- Each register holds **VLMAX = 32 elements** of 32 bits each
- Total storage: 8 x 32 x 32 = 8192 bits = 1 KB
- 2 read ports, 1 write port (per lane)
- Why 8 registers (not 32): keeps encoding compact, sufficient for most vectorized
  loops, reduces hardware cost. Real RISC-V V uses 32 but we're a teaching design.

### 3.3 SIMD Lanes

- **4 parallel lanes**, each with its own ALU
- Each ALU supports: add, sub, mul, div, rem, and, or, xor, sll, srl, sra, comparisons
- For VL=32, processing takes 32/4 = **8 cycles** per vector operation
- Lanes share the same control signals (true SIMD)

### 3.4 Vector Mask Register

- 32-bit register (1 bit per element)
- Set by comparison instructions (VSEQ, VSLT, etc.)
- Cleared to all-1s by CVM
- When mask bit is 0, that lane's write-back is suppressed (element unchanged)

### 3.5 Command Queue

- **4-entry FIFO** between scalar core and vector unit
- Each entry holds: opcode, funct3, funct7, vd, vs1, vs2, scalar_value, vector_length
- Scalar core stalls only when queue is full
- VFENCE stalls scalar core until queue is empty AND vector unit is idle

### 3.6 Stripmining

- If the application vector length > VLMAX (32), the compiler/programmer uses SETVL
  in a loop (strip-mine loop)
- SETVL sets VL = min(requested_length, 32), returns actual VL in rd
- The vector unit always processes exactly VL elements

### 3.7 Memory Interface for Vector Loads/Stores

- Vector unit shares the data memory port with scalar core
- During VLW/VSW: vector unit issues VL sequential word requests (one per cycle)
- During VLWS/VSWS: vector unit issues VL strided requests
- Scalar core's memory stage is stalled while vector memory op is in progress
- Alternative considered: dual-port memory -- decided against to match existing
  memory infrastructure

---

## 4. Project Phases

### Phase 0: Project Setup & Instruction Encoding
- Create `vector-coprocessor/` directory
- Copy `riscvbyp/`, `vc/`, `imuldiv/`, `tests/`, `build/` from A3
- Update `InstMsg.v` with vector instruction decode fields
- Define custom-0 opcode constants
- **Testing checkpoint**: Existing scalar tests still pass unchanged

### Phase 1: Scalar Core Modifications
- Modify `CoreCtrl.v` to detect vector instructions in decode stage
- On vector instruction: extract operands, assert val on coprocessor interface
- For VFENCE: stall pipeline until coprocessor asserts `idle`
- For SETVL: could be handled in scalar core (write VL to a CSR-like register
  and also forward to vector unit)
- For VREDSUM: result comes back from vector unit to scalar register file
- **Testing checkpoint**: Scalar core correctly identifies vector instructions
  and does not crash (NOP behavior initially)

### Phase 2: Vector Register File & Datapath
- Implement `VecRegfile.v`: 8 x 32 x 32-bit, multi-ported per lane
- Implement `VecAlu.v`: 4 parallel ALUs, each supporting all arithmetic/logic ops
- Implement `VecDpath.v`: wiring regfile -> ALU -> writeback with mask gating
- Implement `VecMaskReg.v`: 32-bit mask register with CVM and comparison writes
- **Testing checkpoint**: Unit tests for regfile read/write, ALU correctness

### Phase 3: Vector Coprocessor Control FSM
- Implement `VecCtrl.v`: state machine with states:
  - IDLE: waiting for command
  - EXECUTE: processing VL/4 cycles of arithmetic
  - LOAD: issuing memory read requests
  - STORE: issuing memory write requests
  - REDUCE: performing tree reduction
  - DONE: signaling completion
- Handle element iteration (4 elements per cycle, iterate VL/4 times)
- Mask predication: suppress write-back when mask bit is 0
- **Testing checkpoint**: FSM transitions correctly for each instruction type

### Phase 4: Memory Interface (VLW/VSW/VLWS/VSWS)
- Vector load: issue VL word-reads, collect responses into vector register
- Vector store: issue VL word-writes from vector register
- Strided variants: address = base + i * stride
- Arbitration: scalar memory stage stalls during vector memory ops
- **Testing checkpoint**: Can load a vector from memory and store it back

### Phase 5: Integration & Correctness Testing
- Wire `VecUnit` into `riscv-Core.v` top-level
- Write assembly test for each instruction:
  - `riscv-vvadd.S`, `riscv-vsadd.S`, `riscv-vvmul.S`, etc.
  - `riscv-vlw.S`, `riscv-vsw.S`, `riscv-vlws.S`
  - `riscv-vseq.S`, `riscv-vslt.S` (mask tests)
  - `riscv-vredsum.S` (reduction test)
  - `riscv-vfence.S` (synchronization test)
  - `riscv-setvl.S` (configuration test)
- Build test macros in `riscv-macros.h` for vector instructions
- **Testing checkpoint**: All 33 instructions pass individual tests

### Phase 6: Benchmarking & Performance Analysis
- **Benchmark programs**:
  1. DAXPY: y[i] = a*x[i] + y[i] (high parallelism)
  2. Vector dot product (reduction-heavy)
  3. Conditional vector update (mask-heavy)
  4. Mixed scalar/vector workload (varying ratios)
  5. Matrix-vector multiply (uses strided access)
- **Metrics to collect**:
  - Total cycles (scalar-only vs scalar+vector)
  - Speedup factor
  - Vector unit utilization (% of cycles vector unit is busy)
  - Queue occupancy statistics
  - Impact of VL on performance
- **Testing checkpoint**: Clean data for report charts

### Phase 7 (Stretch): OOO Integration
- Integrate vector coprocessor into `riscvooo`
- Vector commands must interact with scoreboard (mark destination as pending)
- ROB must track vector instructions for in-order commit
- Compare: bypassing+vector vs OOO+vector

---

## 5. Design Decisions Log

| Decision | Rationale | Date |
|----------|-----------|------|
| Base processor: riscvbyp | Best balance of performance and modifiability | 2026-05-03 |
| Decoupled (not tightly coupled) | Allows scalar core to continue executing; matches real designs | 2026-05-03 |
| Custom-0 opcode (0x0B) | RISC-V reserved for extensions; avoids conflicts | 2026-05-03 |
| 8 vector registers | Compact 3-bit encoding; sufficient for teaching design | 2026-05-03 |
| VLMAX = 32 elements | Matches proposal; reasonable for 4-lane, 8-cycle execution | 2026-05-03 |
| 4 SIMD lanes | Good parallelism without excessive hardware; 8 cycles per full vector | 2026-05-03 |
| 4-entry command queue | Allows modest decoupling without large buffering cost | 2026-05-03 |
| Skip scatter/gather initially | Very complex memory access patterns; stretch goal | 2026-05-03 |
| Include mask/comparison | Enables conditional vectorization; significant capability | 2026-05-03 |
| Include strided loads | Enables matrix column access; moderate complexity | 2026-05-03 |
| Include REM/REMU vector ops | Differentiator from VMIPS; leverages existing scalar ALU | 2026-05-03 |
| Shared memory port (not dual) | Matches existing infrastructure; simpler arbitration | 2026-05-03 |
| 33 total instructions | Comprehensive ISA covering arith, logic, mem, mask, reduce, config | 2026-05-03 |

---

## 6. Related Work References (for report)

- Cray-1 (1976): First commercial vector processor, 8 vector registers x 64 elements
- VMIPS: Textbook vector ISA from Hennessy & Patterson
- RISC-V V Extension: Official scalable vector extension (v1.0 ratified 2021)
- Hwacha (UC Berkeley): Decoupled vector accelerator for RISC-V
- ARM SVE: Scalable Vector Extensions with predication
- Intel AVX-512: Fixed-width SIMD with mask registers

---

## 7. File Organization

```
vector-coprocessor/
  riscvvec/                    # Our modified processor
    riscvvec-Core.v            # Top-level: scalar core + vector unit
    riscvvec-CoreCtrl.v        # Modified scalar control (vector dispatch)
    riscvvec-CoreDpath.v       # Modified scalar datapath
    riscvvec-VecUnit.v         # Vector coprocessor top-level
    riscvvec-VecCtrl.v         # Vector FSM controller
    riscvvec-VecDpath.v        # Vector datapath
    riscvvec-VecRegfile.v      # Vector register file (8x32x32b)
    riscvvec-VecAlu.v          # 4-lane SIMD ALU
    riscvvec-VecMaskReg.v      # 32-bit vector mask register
    riscvvec-VecCmdQueue.v     # Command queue (4-entry FIFO)
    riscvvec-InstMsg.v         # Updated instruction decode
    riscvvec-sim.v             # Simulation harness
  vc/                          # Verilog components (from A3)
  imuldiv/                     # Mul/div unit (from A3)
  tests/
    riscv/
      riscv-vvadd.S            # Vector-vector add test
      riscv-vsadd.S            # Vector-scalar add test
      ... (one per instruction)
      riscv-daxpy.S            # DAXPY benchmark
      riscv-vdot.S             # Dot product benchmark
      riscv-macros.h           # Updated with vector test macros
  build/                       # Build scripts
```

---

## 8. Test Results Summary

### Build & Run Commands
```bash
source /home/ECE475/env_spr2026.sh
cd tests && mkdir build && cd build && ../configure --host=riscv32-unknown-elf && make && ../convert
cd ../../build && make riscvvec-sim
./riscvvec-sim +exe=../tests/build/vmh/riscv-vec.vmh +stats=1
```

### Test Coverage (riscv-vec.S)

| Test | Instructions Tested | What It Verifies |
|------|-------------------|------------------|
| Test 1 | SETVL | Set vector length to 4 |
| Test 2 | VLW, VSW, VFENCE | Load vector from memory, store back, scalar verify |
| Test 3 | VVADD | Vector-vector addition: [10,20,30,40]+[1,2,3,4]=[11,22,33,44] |
| Test 4 | VVSUB | Vector-vector subtraction: [10,20,30,40]-[1,2,3,4]=[9,18,27,36] |
| Test 5 | VVMUL | Vector-vector multiply: [10,20,30,40]*[1,2,3,4]=[10,40,90,160] |
| Test 6 | VSADD | Vector-scalar add: [10,20,30,40]+100=[110,120,130,140] |
| Test 7 | VSMUL | Vector-scalar multiply: [1,2,3,4]*3=[3,6,9,12] |
| Test 8 | SETVL (VL=1) | Edge case: single element operations |
| Test 9 | Negative numbers | [-1,-10,-100,-1000]+[1,2,3,4]=[0,-8,-97,-996] |
| Test 10 | VVAND, VVOR, VVXOR | Bitwise operations with complementary patterns |
| Test 11 | VSSUB | Vector-scalar subtract: [10,20,30,40]-5=[5,15,25,35] |
| Test 12 | Decoupled ops | Multiple vector ops queued without intermediate VFENCE |
| Test 13 | VL=0 edge case | Zero-length operations don't modify memory |

### Results
- **All 43 scalar tests: PASSED**
- **Vector test (riscv-vec.S): PASSED**
- **Total: 44/44 tests pass**

### Key Bugs Found and Fixed During Development
1. **VSW base address routing**: VSW uses rs2 field for base address (not rs1), required special handling in Core.v command packing
2. **Registered vs combinational outputs**: VecCtrl originally used registered outputs causing 1-cycle delay in elem_idx/vs1_addr, meaning wrong data was read. Fixed by making all datapath control signals combinational.
3. **Memory arbitration**: Initial approach using `vec_memreq_val` to gate memory access failed because the signal goes low during LWAIT. Fixed by using `!vec_idle` to determine vector memory ownership.
4. **SWAIT state eliminated**: Zero-latency memory doesn't need a wait state between stores. Stores process one per cycle.


---

## 9. Benchmark Performance Results

### Custom Assembly Benchmarks: Scalar vs Vector

| Benchmark | Impl | Cycles | Instructions | IPC | Speedup |
|-----------|------|--------|-------------|-----|---------|
| VVADD (32 elem) | Scalar | 452 | 323 | 0.71 | 1.00x |
| VVADD (32 elem) | **Vector** | **242** | 44 | 0.18 | **1.87x** |
| DAXPY (32 elem) | Scalar | 1475 | 322 | 0.22 | 1.00x |
| DAXPY (32 elem) | **Vector** | **274** | 44 | 0.16 | **5.38x** |
| SAXPY (16 elem) | Scalar | 739 | 146 | 0.20 | 1.00x |
| SAXPY (16 elem) | **Vector** | **112** | 42 | 0.38 | **6.60x** |

### Analysis

**VVADD (1.87x speedup):**
- Scalar: 32 iterations x ~14 cycles/iter (load-load-add-store + pointer increments + branch)
- Vector: 2 VLW (32+32 mem ops) + 1 VVADD (32 ALU ops) + 1 VSW (32 mem ops) + VFENCE
- Bottleneck is memory bandwidth: loads/stores are serialized (1 per cycle)
- Speedup comes from eliminating loop overhead (32 branches, 96 pointer increments)

**DAXPY (5.38x speedup):**
- Scalar: 32 iterations with MUL (multi-cycle latency!) + load + add + store
- Vector: MUL is single-cycle in vector ALU (combinational), no pipeline stalls
- Huge savings from avoiding 32 multi-cycle scalar multiply stalls
- This is the ideal vector workload: compute-bound with regular memory access

**SAXPY (6.60x speedup):**
- Similar to DAXPY but with 16 elements
- Even higher relative speedup due to MUL latency dominating scalar version
- Shows that even small vectors benefit significantly from vector acceleration

### Existing C Benchmarks (scalar-only, verify no regression)

| Benchmark | Cycles | Instructions | IPC |
|-----------|--------|-------------|-----|
| ubmark-vvadd (100 elem) | 471 | 453 | 0.96 |
| ubmark-bin-search | 1497 | 1017 | 0.68 |
| ubmark-cmplx-mult | 15150 | 1723 | 0.11 |
| ubmark-masked-filter | 13933 | 4931 | 0.35 |

All existing benchmarks pass unchanged, confirming no performance regression on scalar code.

### Key Observations

1. **Compute-bound kernels benefit most**: DAXPY/SAXPY with MUL see 5-6x speedup because
   the vector ALU avoids the multi-cycle scalar multiplier pipeline stalls.

2. **Memory-bound kernels still benefit**: VVADD gets 1.87x even though loads/stores are
   serialized, because loop overhead (branches, pointer math) is eliminated.

3. **IPC appears low for vector code** because the scalar pipeline counts fewer "instructions"
   (the vector ops look like single instructions to the scalar core). The actual throughput
   (operations per cycle) is much higher.

4. **Decoupled execution helps**: The scalar core continues fetching/decoding while the vector
   unit processes, overlapping setup with computation.

