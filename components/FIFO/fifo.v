// Setting up the time step
`timescale 1ns/100ps

/*
======================================================================
Module: Simple Dual-Port RAM
Description: Acts as the physical storage matrix. Offers decoupled
             read and write address lines for independent operations.
======================================================================
*/

module SDP_RAM #(
    parameter DATA_WIDTH = 8,
    parameter FIFO_DEPTH = 256
)(
    input  wire [DATA_WIDTH-1 +2:0] IN,
    output reg  [DATA_WIDTH-1 +2:0] OUT,

    input  wire [$clog2(FIFO_DEPTH)-1:0] INADDRESS,
    input  wire [$clog2(FIFO_DEPTH)-1:0] OUTADDRESS,

    input  wire WRITE,
    input  wire CLK
);

    parameter ADDR_WIDTH = $clog2(FIFO_DEPTH);

    
    // Register Storage Declaration
    reg [DATA_WIDTH-1 +2:0] registers [0:FIFO_DEPTH-1];
    
    // Iterator as a helper for reset loops
    integer i;


    // Write and Reset triggeres on the positive edge of the clock
    always @(posedge CLK) 
    begin

        if (WRITE) begin
            // load IN data to specified INADDRESS with a #1 delay
            // Synchronus writing is used
            #1 registers[INADDRESS] <= IN;
            // Used delay for realistic latency
        end
    end


    // Read Logic for Outputs
    // Asynchronus
    // Updates whenever the address or target register data changes
    always @(*)
    begin
    // Artificial delay of 1 time units for realistic reading latency
    #1;
    OUT = registers[OUTADDRESS];
    end

endmodule



/*
======================================================================
Module: Pointer Controller & Status Logic
Description: Computes real-time buffer volume metrics, manages bounds, 
             and provides flow-control thresholds.
======================================================================
*/
module FIFO_Controller #(
    parameter FIFO_DEPTH = 256
)(  
    // Input Control Signals
    input wire READ_ENABLE,
    input wire WRITE_ENABLE,
    input wire CLK,
    input wire RESET,

    // address pointers
    output wire [$clog2(FIFO_DEPTH)-1:0] READ_ADDRESS,
    output wire [$clog2(FIFO_DEPTH)-1:0] WRITE_ADDRESS,

    // Status flags
    output wire FULL,
    output wire EMPTY,
    output wire ALMOST_FULL
);

    parameter ADDR_POINTER_LENGTH = $clog2(FIFO_DEPTH);

    // ADDR_POINTER_LENGTH+1 bits wide
    // {lap_counter, pointer}
    reg [ADDR_POINTER_LENGTH:0] wr_ptr;
    reg [ADDR_POINTER_LENGTH:0] rd_ptr;


    // flag setup

    assign EMPTY = (wr_ptr == rd_ptr);

    assign FULL =
        (wr_ptr[ADDR_POINTER_LENGTH-1:0] == rd_ptr[ADDR_POINTER_LENGTH-1:0]) &&
        (wr_ptr[ADDR_POINTER_LENGTH] != rd_ptr[ADDR_POINTER_LENGTH]);


    // Calculate actual occupancy using pointer subtraction
    wire [ADDR_POINTER_LENGTH:0] occupancy = wr_ptr - rd_ptr;
    assign ALMOST_FULL = (occupancy >= (FIFO_DEPTH*3/4)); // High-water mark for flow control


    // output setup
    // Continuous assignments for memory addresses
    assign WRITE_ADDRESS = wr_ptr[ADDR_POINTER_LENGTH-1:0];
    assign READ_ADDRESS = rd_ptr[ADDR_POINTER_LENGTH-1:0];

    initial begin
        // Pointer Initiation
        wr_ptr = '0;
        rd_ptr = '0;
    end


    // Triggeres on the positive edge of the clock
    always @(posedge CLK) 
    begin

        if (RESET) begin  // if RESET is 1
            #1 // delay for relisticity
            wr_ptr <= '0;
            rd_ptr <= '0;
        end

        if (READ_ENABLE && !EMPTY) begin

            #1 // realistic delay

            // if pointer part is all 1s
            if (& rd_ptr[ADDR_POINTER_LENGTH-1:0]) begin

                // lap_counter flip
        
                rd_ptr[ADDR_POINTER_LENGTH-1:0] <= '0;
                rd_ptr[ADDR_POINTER_LENGTH] <= ~rd_ptr[ADDR_POINTER_LENGTH];
            end

            else begin
                rd_ptr[ADDR_POINTER_LENGTH-1:0] <= rd_ptr[ADDR_POINTER_LENGTH-1:0] + 1'b1;
            end
            
        end

        if (WRITE_ENABLE && !FULL) begin

            // if pointer part is all 1s
            if (& wr_ptr[ADDR_POINTER_LENGTH-1:0]) begin

                // lap_counter flip

                wr_ptr[ADDR_POINTER_LENGTH-1:0] <= '0;
                wr_ptr[ADDR_POINTER_LENGTH] <= ~ wr_ptr[ADDR_POINTER_LENGTH];
            end

            else begin
                wr_ptr[ADDR_POINTER_LENGTH-1:0] <= wr_ptr[ADDR_POINTER_LENGTH-1:0] + 1'b1;
            end
            
        end

    end
endmodule



/*
======================================================================
Module: Top-Level FIFO Wrapper
Description: Merges data and boundary tags into unified records 
             to safely govern real-time structural switch operations.
======================================================================
*/

module FIFO #(
    parameter DATA_WIDTH = 8,
    parameter FIFO_DEPTH = 256
)(
    input wire CLK,
    input wire RESET,
    input wire READ_ENABLE,
    input wire WRITE_ENABLE,

    input wire [DATA_WIDTH-1:0] DATA_IN,
    input wire DIN_SOP,
    input wire DIN_EOP,

    output wire [DATA_WIDTH-1:0] DATA_OUT,
    output wire DOUT_SOP,
    output wire DOUT_EOP,

    output wire FULL,
    output wire EMPTY,
    output wire ALMOST_FULL
);

    // Internal signals
    wire [$clog2(FIFO_DEPTH)-1:0] read_addr;
    wire [$clog2(FIFO_DEPTH)-1:0] write_addr;

    // Ingress, Egress Setup
    wire [DATA_WIDTH -1+2:0] ingress;
    wire [DATA_WIDTH -1+2:0] egress;

    assign ingress = {DATA_IN, DIN_SOP, DIN_EOP};
    assign {DATA_OUT, DOUT_SOP, DOUT_EOP} = egress;

    //--------------------------------------------------
    // FIFO Controller Instance
    FIFO_Controller #(
        .FIFO_DEPTH(FIFO_DEPTH)
    ) fifo_ctrl (
        .READ_ENABLE  (READ_ENABLE),
        .WRITE_ENABLE (WRITE_ENABLE),
        .CLK          (CLK),
        .RESET        (RESET),

        .READ_ADDRESS (read_addr),
        .WRITE_ADDRESS(write_addr),

        .FULL         (FULL),
        .EMPTY        (EMPTY),
        .ALMOST_FULL  (ALMOST_FULL)
    );

    //--------------------------------------------------
    // Memory Block RAM Instance
    SDP_RAM #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) ram (
        .IN         (ingress),
        .OUT        (egress),

        .INADDRESS  (write_addr),
        .OUTADDRESS (read_addr),

        .WRITE      (WRITE_ENABLE),
        .CLK        (CLK)
    );

endmodule