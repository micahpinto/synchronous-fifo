# synchronous-fifo
Synchronous FIFO in SystemVerilog, two designs: count-based (used to fix a burst bug in my UART project) and lap-bit pointers. Verified with a self-checking testbench: queue reference model, directed corner cases and 5,000 random cycles.
