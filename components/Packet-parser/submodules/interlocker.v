`timescale 1ns / 100ps

/*
================================================================================================================
Module: Output Gating & Interlock Logic
Description: Handles downstream stream gating, bypass data routing, 
             and cut-through SOP marker generation.
============================================================================================================
*/

module interlocker (

    // global signals
    input wire        clk,
    input wire        rst,           // Active high synchronous reset
    
    // from FSM
    input wire         metadata_valid,
    
    // Upstream Control Inputs (From FIFO)
    input  wire        fifo_valid,
    input  wire        fifo_sop,
    output wire        fifo_read,       // Backpressure fed backward

    // Downstream Control Interface (To Fabric)
    input  wire        fabric_ready,     // Backpressure from fabric
    output wire        parsed_sop,       // Fabricated new SOP marker
    output wire        parsed_valid     // Gated valid line
);    

    // Internal tracking register for delayed version of signal
    reg sig_d;      

    assign fifo_read = fabric_ready;    //back preassure propoagation

    initial begin
        sig_d        = 1'b0;
    end

    // for positive edge detection of metadata_valid
    always @(posedge clk) begin
        if (rst || fifo_sop) begin
            sig_d <= 1'b0;
        end else begin
            sig_d <= metadata_valid;
        end
    end

    // New SOP generation
    // when metadata_valid goes high, active for exactly 1 cycle
    assign parsed_sop = metadata_valid & (~sig_d) & fifo_valid;

    // Control signal for fabric
    assign parsed_valid = metadata_valid & fifo_valid;

endmodule