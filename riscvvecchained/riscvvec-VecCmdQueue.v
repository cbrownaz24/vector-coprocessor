//=========================================================================
// vec cmd queue (chained version)
//=========================================================================
// 4-entry fifo btwn scalar core and vec unit. exposes head AND 2nd entry
// so ctrl can spot chaining and deq two in one cycle.

`ifndef RISCV_VEC_CMD_QUEUE_V
`define RISCV_VEC_CMD_QUEUE_V

module riscv_VecCmdQueue
(
  input         clk,
  input         reset,

  // enq side - from scalar core
  input         enq_val,
  output        enq_rdy,
  input  [118:0] enq_msg,

  // deq head
  output        deq_val,
  input         deq_rdy,
  output [118:0] deq_msg,

  // peek 2nd slot for chaining
  output        deq_val_2,
  output [118:0] deq_msg_2,
  input         deq_rdy_2,    // high w/ deq_rdy -> double-deq

  // status
  output        empty,
  output        full
);

  localparam NUM_ENTRIES = 4;
  localparam PTR_SZ = 2;

  reg [118:0] entries [0:NUM_ENTRIES-1];
  reg [PTR_SZ:0] head;
  reg [PTR_SZ:0] tail;

  wire [PTR_SZ-1:0] head_idx = head[PTR_SZ-1:0];
  wire [PTR_SZ-1:0] tail_idx = tail[PTR_SZ-1:0];
  wire [PTR_SZ-1:0] head_idx_p1 = head_idx + 1'b1;

  // occupancy = tail - head w/ extra msb for wrap
  wire [PTR_SZ:0] occupancy = tail - head;

  assign empty = (head == tail);
  assign full  = (head_idx == tail_idx) && (head[PTR_SZ] != tail[PTR_SZ]);

  assign enq_rdy = !full;
  assign deq_val = !empty;
  assign deq_msg = entries[head_idx];

  // 2nd entry only valid if >=2 occupied
  assign deq_val_2 = (occupancy >= 3'd2);
  assign deq_msg_2 = entries[head_idx_p1];

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
      // single or double deq
      if (deq_val && deq_rdy) begin
        if (deq_rdy_2 && deq_val_2)
          head <= head + 2;
        else
          head <= head + 1;
      end
    end
  end

endmodule

`endif
