// Synchronous FIFO, method B: no count register.
// Each pointer has one extra "lap" bit; full and empty come from comparing the pointers.
// Same ports and behaviour as fifo_count (method A),so the testbench is similar
// DEPTH must be a power of 2 (4, 8, 16, ...) so the pointers wrap by themselves.
module fifo_lapbit #(
  parameter int WIDTH = 8,     // bits per slot
  parameter int DEPTH = 16     // number of slots
)(
  input  logic             i_Clk,
  // write side
  input  logic             i_Wr_En,
  input  logic [WIDTH-1:0] i_Wr_Data,
  // read side
  input  logic             i_Rd_En,
  output logic [WIDTH-1:0] o_Rd_Data,
  // status
  output logic             o_Empty,
  output logic             o_Full
);

  localparam int PTR_W = $clog2(DEPTH);       // 16 slots-4 bits to pick a slot

  //storage
  logic [WIDTH-1:0] r_Mem [DEPTH];            // DEPTH slots (same as [0:DEPTH-1])
  logic [PTR_W:0]   r_Wr_Ptr = '0;            // one extra bit: [PTR_W] = lap, [PTR_W-1:0] = slot
  logic [PTR_W:0]   r_Rd_Ptr = '0;

  //safety rules
  logic w_Wr, w_Rd;
  assign w_Wr = i_Wr_En && !o_Full;           // never write when full
  assign w_Rd = i_Rd_En && !o_Empty;          // never read when empty

  //write and read
  always_ff @(posedge i_Clk) begin
    if (w_Wr) begin
      r_Mem[r_Wr_Ptr[PTR_W-1:0]] <= i_Wr_Data;   // slot bits only pick the slot
      r_Wr_Ptr <= r_Wr_Ptr + 1'b1;               // lap bit flips after the last slot
    end

    if (w_Rd)
      r_Rd_Ptr <= r_Rd_Ptr + 1'b1;
  end

  //outputs
  assign o_Rd_Data = r_Mem[r_Rd_Ptr[PTR_W-1:0]];   // front byte, always visible

  // empty: same slot AND same lap
  assign o_Empty = (r_Wr_Ptr == r_Rd_Ptr);

  // full: same slot, different lap (the writer is one lap ahead)
  assign o_Full  = (r_Wr_Ptr[PTR_W]     != r_Rd_Ptr[PTR_W]) &&
                   (r_Wr_Ptr[PTR_W-1:0] == r_Rd_Ptr[PTR_W-1:0]);

endmodule