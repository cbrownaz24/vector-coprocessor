//=========================================================================
// Vector Command Queue
//=========================================================================
// 4-entry FIFO queue between the scalar core and the vector unit.
// Each entry stores the decoded vector command from the scalar core.
//
// Command format (total CMD_SZ bits):
//   [6:0]   opcode_fn  - combined funct3 + funct7 encoding
//   [2:0]   vd         - destination vector register
//   [2:0]   vs1        - source vector register 1
//   [2:0]   vs2        - source vector register 2 / scalar reg addr
//   [31:0]  scalar_val - scalar operand value (from scalar register file)
//   [31:0]  base_addr  - base address for memory ops
//   [31:0]  stride     - stride for strided memory ops
//   [4:0]   rd_scalar  - scalar destination register (for reductions)

`ifndef RISCV_VEC_CMD_QUEUE_V
`define RISCV_VEC_CMD_QUEUE_V

module riscv_VecCmdQueue
(
  input         clk,
  input         reset,

  // Enqueue interface (from scalar core)
  input         enq_val,
  output        enq_rdy,
  input  [118:0] enq_msg,    // Command message

  // Dequeue interface (to vector unit)
  output        deq_val,
  input         deq_rdy,
  output [118:0] deq_msg,

  // Status
  output        empty,
  output        full
);

  localparam NUM_ENTRIES = 4;
  localparam PTR_SZ = 2;         // log2(4) = 2

  // Storage
  reg [118:0] entries [0:NUM_ENTRIES-1];
  reg [PTR_SZ:0] head;           // Extra bit for full/empty detection
  reg [PTR_SZ:0] tail;

  // Pointer comparison (using extra MSB for wrap-around detection)
  wire [PTR_SZ-1:0] head_idx = head[PTR_SZ-1:0];
  wire [PTR_SZ-1:0] tail_idx = tail[PTR_SZ-1:0];

  assign empty = (head == tail);
  assign full  = (head_idx == tail_idx) && (head[PTR_SZ] != tail[PTR_SZ]);

  assign enq_rdy = !full;
  assign deq_val = !empty;
  assign deq_msg = entries[head_idx];

  always @(posedge clk) begin
    if (reset) begin
      head <= 0;
      tail <= 0;
    end
    else begin
      // Enqueue
      if (enq_val && enq_rdy) begin
        entries[tail_idx] <= enq_msg;
        tail <= tail + 1;
        // Debug (uncomment for debugging)
        // `ifndef SYNTHESIS
        // $display("VEC_QUEUE: ENQ cat=%0d opfn=%07b vd=%0d vs1=%0d vs2=%0d scalar=%08h base=%08h",
        //   enq_msg[118:117], enq_msg[6:0], enq_msg[9:7], enq_msg[12:10], enq_msg[15:13],
        //   enq_msg[47:16], enq_msg[79:48]);
        // `endif
      end
      // Dequeue
      if (deq_val && deq_rdy) begin
        head <= head + 1;
      end
    end
  end

endmodule

`endif
