`timescale 1ns/1ps

// Testbench for fifo_lapbit (method B).
// A reference model (a queue) knows what SHOULD be inside the FIFO.
// Every clock, the FIFO's outputs are compared with the model.
module fifo_lapbit_tb;

  localparam int WIDTH  = 8;
  localparam int DEPTH  = 4;       // small, so full and empty happen often
  localparam int CYCLES = 5000;    // length of the random test

  //FIFO inputs 
  logic             clk     = 0;
  logic             wr_en   = 0;
  logic             rd_en   = 0;
  logic [WIDTH-1:0] wr_data = '0;

  //FIFO outputs
  logic [WIDTH-1:0] rd_data;
  logic             empty;
  logic             full;

  //reference model
  logic [WIDTH-1:0] model [$];     // a queue: push_back on write, pop_front on read
  int errors = 0;

  //coverage counters:all test cases
  int n_writes = 0, n_reads = 0, n_both = 0;
  int n_full = 0, n_empty = 0, n_wr_refused = 0, n_rd_refused = 0;

  always #5 clk = ~clk;

  fifo_lapbit #(.WIDTH(WIDTH), .DEPTH(DEPTH)) DUT (
    .i_Clk     (clk),
    .i_Wr_En   (wr_en),
    .i_Wr_Data (wr_data),
    .i_Rd_En   (rd_en),
    .o_Rd_Data (rd_data),
    .o_Empty   (empty),
    .o_Full    (full)
  );

  //compare the FIFO's outputs with the model
  task automatic check_fifo();
    bit exp_empty = (model.size() == 0);
    bit exp_full  = (model.size() == DEPTH);
    if (empty !== exp_empty) begin
      $display("%0t: empty = %b, expected %b", $time, empty, exp_empty);
      errors++;
    end
    if (full !== exp_full) begin
      $display("%0t: full = %b, expected %b", $time, full, exp_full);
      errors++;
    end
    if (!exp_empty && rd_data !== model[0]) begin
      $display("%0t: front byte = %h, expected %h", $time, rd_data, model[0]);
      errors++;
    end
  endtask

  //one clock: check, then drive new inputs, then update the model
  task automatic step(bit wr, bit rd, logic [WIDTH-1:0] data);
    bit can_wr, can_rd;
    @(negedge clk);                          // middle of the clock: everything is stable

    check_fifo();

    can_wr = (model.size() < DEPTH);         // what the FIFO SHOULD accept
    can_rd = (model.size() > 0);

    wr_en   = wr;                            // drive inputs for the next rising edge
    rd_en   = rd;
    wr_data = data;

    // coverage
    if (!can_rd)          n_empty++;
    if (!can_wr)          n_full++;
    if (wr && !can_wr)    n_wr_refused++;
    if (rd && !can_rd)    n_rd_refused++;
    if (wr && can_wr)     n_writes++;
    if (rd && can_rd)     n_reads++;
    if (wr && rd && can_wr && can_rd) n_both++;

    // model: what the FIFO will hold after the next rising edge
    if (rd && can_rd) void'(model.pop_front());
    if (wr && can_wr) model.push_back(data);
  endtask

  initial begin
    //directed tests
    $display("Directed tests");
    step(1, 0, 8'hA1); step(1, 0, 8'hA2); step(1, 0, 8'hA3);      // 3 writes
    step(0, 1, '0);    step(0, 1, '0);    step(0, 1, '0);         // 3 reads, in order
    for (int i = 0; i < DEPTH; i++) step(1, 0, 8'h10 + i);        // fill up
    step(1, 0, 8'hEE);                                            // write when full: refused
    for (int i = 0; i < DEPTH; i++) step(0, 1, '0);               // drain, EE must not appear
    step(0, 1, '0);                                               // read when empty: refused
    step(1, 0, 8'h55); step(1, 1, 8'h66); step(0, 1, '0);         // write + read in the same clock
    step(0, 0, '0);                                               // one more check

    //random test
    // Four phases: mostly writes, mostly reads, balanced, then anything.
    $display("Random test, %0d cycles", CYCLES);
    for (int i = 0; i < CYCLES; i++) begin
      int p_wr;
      case ((i * 4) / CYCLES)
        0: p_wr = 80;      // fills up - full happens often
        1: p_wr = 20;      // drains - empty happens often
        2: p_wr = 50;
        default: p_wr = $urandom_range(0, 100);
      endcase
      step($urandom_range(0, 99) < p_wr,           // write with probability p_wr %
           $urandom_range(0, 99) < (100 - p_wr),   // read with the rest
           $urandom_range(0, 255));
    end
    step(0, 0, '0);

    //report format
    $display("----------------------------------");
    $display("Accepted: %0d writes, %0d reads, %0d same-clock write+read", n_writes, n_reads, n_both);
    $display("Clocks full: %0d, clocks empty: %0d", n_full, n_empty);
    $display("Refused: %0d writes when full, %0d reads when empty", n_wr_refused, n_rd_refused);
    if (errors == 0) $display("TEST PASSED: 0 errors");
    else             $display("TEST FAILED: %0d errors", errors);
    $display("----------------------------------");
    $finish;
  end

endmodule