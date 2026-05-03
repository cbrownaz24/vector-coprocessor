// 4-entry fifo btwn scalar core and vec unit. each slot holds 1 decoded vec cmd.
`ifndef RISCV_VEC_CMD_QUEUE_V
`define RISCV_VEC_CMD_QUEUE_V

// CMD_QUEUE_DEPTH/PTR_SZ overridable at compile time via iverilog -DVEC_CMD_QUEUE_DEPTH=8 -DVEC_CMD_QUEUE_PTR_SZ=3; must set both
// NOTE: PTR_SZ = log2(DEPTH)
`ifndef VEC_CMD_QUEUE_DEPTH
  `define VEC_CMD_QUEUE_DEPTH 4
`endif
`ifndef VEC_CMD_QUEUE_PTR_SZ
  `define VEC_CMD_QUEUE_PTR_SZ 2
`endif

module riscv_VecCmdQueue
(
  input clk,
  input reset,

  // enq side (from scalar core)
  input enq_val,
  output enq_rdy,
  input [118:0] enq_msg,

  // deq side (to vec unit)
  output deq_val,
  input deq_rdy,
  output [118:0] deq_msg,

  output empty,
  output full
);

  localparam NUM_ENTRIES = `VEC_CMD_QUEUE_DEPTH;
  localparam PTR_SZ = `VEC_CMD_QUEUE_PTR_SZ;  // log2(NUM_ENTRIES)

  reg [118:0] entries [0:NUM_ENTRIES-1];
  reg [PTR_SZ:0] head;  // extra bit to tell full vs empty
  reg [PTR_SZ:0] tail;

  // ptr cmp, msb tracks wrap
  wire [PTR_SZ-1:0] head_idx = head[PTR_SZ-1:0];
  wire [PTR_SZ-1:0] tail_idx = tail[PTR_SZ-1:0];

  assign empty = (head == tail);
  assign full = (head_idx == tail_idx) && (head[PTR_SZ] != tail[PTR_SZ]);

  assign enq_rdy = !full;
  assign deq_val = !empty;
  assign deq_msg = entries[head_idx];

  always @(posedge clk) begin
    if (reset) begin
      head <= 0;
      tail <= 0;
    end
    else begin
      if (enq_val && enq_rdy) begin
        entries[tail_idx] <= enq_msg;
        tail <= tail + 1;
      end
      if (deq_val && deq_rdy) begin
        head <= head + 1;
      end
    end
  end

endmodule

`endif
