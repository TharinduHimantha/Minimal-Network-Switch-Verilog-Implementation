`timescale 1ns / 100ps


/*
================================================================================================================
Module: The Parsing FSM & Counter Engine
Description: Tracking signals to step through the packet structure
             cycle-by-cycle.
============================================================================================================
*/

module l2_parser_fsm_engine (
    input  wire        clk,
    input  wire        rst,           // Active high synchronous reset

    // Upstream Control Signals (From FIFO)
    input  wire        fifo_sop,
    input  wire        fifo_eop,
    input  wire        fifo_valid,
    
    // Downstream Control Signal (From Fabric)
    input  wire        fabric_ready,

    // Look-ahead Data Interface (For dynamic VLAN routing evaluation)
    input  wire [7:0]  fifo_data,       // Read combinationally to spot 0x81

    // Control Outputs to Component B (Shifter Array)
    output reg  [2:0]  current_state,
    output reg         shift_en,        // Tells shifters to step forward
    // output reg         latch_metadata,  // Strobe to snapshot finalized shifters to output ports
    
    // Status Outputs to Switch Fabric
    output reg         metadata_valid,  // Latched fields are stable and ready for lookup  // merged with latch_metadata
    output reg         runt_error       // Strobe indicating a truncated packet was dropped
);

    //------------------------------------------------------------------------
    // State Encoding
    localparam STATE_IDLE       = 3'd0,
               STATE_PARSE_DMAC = 3'd1,
               STATE_PARSE_SMAC = 3'd2,
               STATE_PARSE_TYPE = 3'd3,
               STATE_PARSE_VLAN = 3'd4,
               STATE_PAYLOAD    = 3'd5;

    reg [2:0] next_state;
    reg [7:0] type_byte_0;     // To inspect accumulated Type[15:8]
    reg [3:0] byte_cnt;


    // Master Handshake Interlock
    // A transaction only executes when data is available AND the downstream fabric is clear.
    wire tx_ok = fifo_valid && fabric_ready;

    //==============================================================================
    // 1. Next-State Combinational Logic (FSM Transitions)

    always @(*) begin
        next_state = current_state;
        
        case (current_state)
            STATE_IDLE: begin
                // Synchronize and start tracking on a valid Start-of-Packet
                if (fifo_valid && fifo_sop && fabric_ready)
                    next_state = STATE_PARSE_DMAC;
            end

            STATE_PARSE_DMAC: begin
                if (tx_ok) begin
                    if (fifo_eop)          next_state = STATE_IDLE; // Runt Error Trap
                    else if (byte_cnt == 5) next_state = STATE_PARSE_SMAC;
                end
            end

            STATE_PARSE_SMAC: begin
                if (tx_ok) begin
                    if (fifo_eop)          next_state = STATE_IDLE; // Runt Error Trap
                    else if (byte_cnt == 5) next_state = STATE_PARSE_TYPE;
                end
            end

            STATE_PARSE_TYPE: begin
                if (tx_ok) begin
                    if (fifo_eop) next_state = STATE_IDLE; // Runt Error Trap

                    else if (byte_cnt == 1) begin
                        // Dynamic VLAN Branching: Check if accumulated byte 0 (type_byte_0) 
                        // and the current incoming byte (fifo_data) match 0x8100.
                        if ({type_byte_0, fifo_data} == 16'h8100)
                            next_state = STATE_PARSE_VLAN;
                        else
                            next_state = STATE_PAYLOAD;
                    end
                end
            end

            STATE_PARSE_VLAN: begin
                if (tx_ok) begin
                    if (fifo_eop)          next_state = STATE_IDLE; // Runt Error Trap
                    else if (byte_cnt == 1) next_state = STATE_PAYLOAD;
                end
            end

            STATE_PAYLOAD: begin
                // Remain here passing streaming data at line rate until End-of-Packet
                if (tx_ok && fifo_eop)
                    next_state = STATE_IDLE;
            end

            default: next_state = STATE_IDLE;
        endcase
    end

    //================================================================
    // 2. Sequential State and Counter Management

    always @(posedge clk) begin
        if (rst) begin
            current_state   <= STATE_IDLE;
            byte_cnt        <= 4'd0;
            runt_error      <= 1'b0;
            metadata_valid  <= 1'b0;
            type_byte_0     <= 8'd0;
        end else begin
            runt_error <= 1'b0; // Default self-clearing error strobe

            if (tx_ok) begin
                current_state <= next_state;

                // Capture type_byte_0 on the first cycle of TYPE parsing state cleanly
                if (current_state == STATE_PARSE_TYPE && byte_cnt == 0) begin
                    type_byte_0 <= fifo_data;
                end

                // Handle Counter Increment and State Boundary Resets
                if (current_state != next_state) begin
                    byte_cnt <= 4'd0; // Reset internal counter on state transitions
                end else begin
                    byte_cnt <= byte_cnt + 1'b1; // Otherwise increment step-by-step
                end

                // Detect Early EOP (Runt Trap Trigger)
                if (fifo_eop && (current_state != STATE_PAYLOAD && current_state != STATE_IDLE)) begin
                    runt_error <= 1'b1;
                end

                // Manage Status Flags
                if (next_state == STATE_PAYLOAD && current_state != STATE_PAYLOAD) begin
                    metadata_valid <= 1'b1; // Metadata successfully locked and validated
                end else if (next_state == STATE_IDLE) begin
                    metadata_valid <= 1'b0; // Clear validation flag for next packet
                end

            end else if (!fifo_valid && fabric_ready && current_state != STATE_IDLE) begin
                // Edge Case: If FIFO goes empty abruptly without EOP, 
                // the FSM freezes state but keeps counters protected.
                current_state <= current_state;
            end
        end
    end

    //=========================================================
    // 3. Shifter & Latch Enable Generation (Control Outputs)

    always @(*) begin
        // Shift registers in Component B should only move during active header states
        // when a valid handshake transaction actually takes place.
        if (tx_ok && (current_state == STATE_PARSE_DMAC || 
                      current_state == STATE_PARSE_SMAC || 
                      current_state == STATE_PARSE_TYPE || 
                      current_state == STATE_PARSE_VLAN)) begin
            shift_en = 1'b1;
        end else begin
            shift_en = 1'b0;
        end

        // Trigger the output latch strobe on the exact transition edge into PAYLOAD state
        // if (tx_ok && (next_state == STATE_PAYLOAD && current_state != STATE_PAYLOAD)) begin
        //     latch_metadata = 1'b1;
        // end else begin
        //     latch_metadata = 1'b0;
        // end
    end

endmodule