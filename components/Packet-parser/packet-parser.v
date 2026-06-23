`timescale 1ns / 100ps

/*
================================================================================================================
Module: PACKET_PARSER (Top-Level Wrapper)
Description: Integrates the FSM Engine, Data Shifter Matrix, and Output Gate Controller 
             to parse L2 headers (including optional 802.1Q VLAN tags) with zero cut-through latency.
============================================================================================================
*/

module PACKET_PARSER (
    // Global Clock and Reset
    input  wire         CLK,
    input  wire         RESET,

    // Upstream Stream Interface (From FIFO Buffer)
    input  wire [7:0]   FIFO_DATA,
    input  wire         FIFO_SOP,
    input  wire         FIFO_EOP,
    input  wire         FIFO_VALID,
    output wire         FIFO_READ,

    // Downstream Stream Interface (To Switch Fabric Matrix)
    output wire [7:0]   PARSED_DATA,
    output wire         PARSED_SOP,
    output wire         PARSED_EOP,
    output wire         PARSED_VALID,
    input  wire         FABRIC_READY,

    // Extracted Network Metadata Output Ports
    output wire [47:0]  OUT_DMAC,
    output wire [47:0]  OUT_SMAC,
    output wire [15:0]  OUT_ETHERTYPE,
    output wire [11:0]  OUT_VLAN_ID,
    output wire [3:0]   OUT_LAST_BYTE_REMAINDER,
    output wire         VLAN_DATA_PRESENT,
    
    // Status Monitoring Flags
    output wire         RUNT_ERROR
);

    //==============================================================================
    // Internal Signal Interconnects

    wire [2:0] internal_current_state;
    wire       internal_shift_en;
    wire       internal_metadata_valid;
    wire       internal_runt_error;

    // Pass internal error flags up to the top level output status port
    assign RUNT_ERROR = internal_runt_error;

    // passes straight through to downstream fabric
    assign PARSED_DATA = FIFO_DATA;
    assign PARSED_EOP  = FIFO_EOP;

    //==============================================================================
    // Parsing FSM & Counter Engine
    l2_parser_fsm_engine u_fsm_engine (
        .clk            (CLK),
        .rst            (RESET),
        .fifo_sop       (FIFO_SOP),
        .fifo_eop       (FIFO_EOP),
        .fifo_valid     (FIFO_VALID),
        .fabric_ready   (FABRIC_READY),
        .fifo_data      (FIFO_DATA),
        .current_state  (internal_current_state),
        .shift_en       (internal_shift_en),
        .metadata_valid (internal_metadata_valid),
        .runt_error     (internal_runt_error)
    );

    //==============================================================================
    // Data Shifter & Accumulator Array

    data_shifter u_data_shifter (
        .clk                     (CLK),
        .rst                     (RESET),
        .runt_error              (internal_runt_error),
        .fifo_data               (FIFO_DATA),
        .current_state           (internal_current_state),
        .shift_en                (internal_shift_en),
        .metadata_valid          (internal_metadata_valid),
        .out_dmac                (OUT_DMAC),
        .out_smac                (OUT_SMAC),
        .out_ethertype           (OUT_ETHERTYPE),
        .out_vlan_id             (OUT_VLAN_ID),
        .out_last_byte_remainder (OUT_LAST_BYTE_REMAINDER),
        .vlan_data_present       (VLAN_DATA_PRESENT)
    );

    //==============================================================================
    // Output Gating & Interlock Logic

    interlocker u_gate_controller (
        .clk            (CLK),
        .rst            (RESET),
        .metadata_valid (internal_metadata_valid),
        .fifo_valid     (FIFO_VALID),
        .fifo_sop       (FIFO_SOP),
        .fifo_read      (FIFO_READ),
        .fabric_ready   (FABRIC_READY),
        .parsed_sop     (PARSED_SOP),
        .parsed_valid   (PARSED_VALID)
    );

endmodule