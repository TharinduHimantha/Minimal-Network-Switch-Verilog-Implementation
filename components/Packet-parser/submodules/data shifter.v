`timescale 1ns / 100ps

/*
================================================================================================================
Module: The Data Shifter & Accumulator Array
Description: Contains the actual raw storage registers that 
            capture the streaming bytes on the fly
============================================================================================================
*/

module data_shifter(

    input wire        clk,
    input wire        rst,           // Active high synchronous reset
    input wire        runt_error,       // Strobe indicating a truncated packet needs to be dropped

    // Look-ahead Data Interface
    input wire [7:0]  fifo_data, 

    // Control Inputs from FSM
    input wire [2:0]  current_state,
    input wire        shift_en,        // Tells shifters to step forward
    
    // Status Outputs from FSM
    input wire        metadata_valid,  // Latched fields are stable and ready for lookup

    //Outputs to switch fabric
    output reg [47:0] out_dmac,
    output reg [47:0] out_smac,
    output reg [15:0] out_ethertype,
    output reg [11:0] out_vlan_id,
    output reg [3:0]  out_last_byte_remainder,
    output reg vlan_data_present // To tell the parser whether vlan data prsent or not
);


    //------------------------------------------------------------------------
    // State Encoding that match with FSM
    localparam STATE_PARSE_DMAC = 3'd1,
               STATE_PARSE_SMAC = 3'd2,
               STATE_PARSE_TYPE = 3'd3,
               STATE_PARSE_VLAN = 3'd4;
    

    // Internal Data Shifters
    reg [47:0] dmac_shifter;
    reg [47:0] smac_shifter;
    reg [15:0] type_shifter;
    reg [15:0] vlan_shifter;

    initial begin
        dmac_shifter = 48'd0;
        smac_shifter = 48'd0;
        type_shifter = 16'd0;
        vlan_shifter = 16'd0;
        vlan_data_present = 1'b0;
    end

    //==========================================================
    // Sequential Shifter Matrix
    always @(posedge clk) begin

        if (rst || runt_error) begin
            dmac_shifter <= 48'd0;
            smac_shifter <= 48'd0;
            type_shifter <= 16'd0;
            vlan_shifter <= 16'd0;
        end
        
        else if (shift_en) begin
            case (current_state)
                STATE_PARSE_DMAC: dmac_shifter <= {dmac_shifter[39:0], fifo_data};
                STATE_PARSE_SMAC: smac_shifter <= {smac_shifter[39:0], fifo_data};
                STATE_PARSE_TYPE: type_shifter <= {type_shifter[7:0],  fifo_data};
                STATE_PARSE_VLAN: vlan_shifter <= {vlan_shifter[7:0],  fifo_data};
                default: ; // Do nothing in IDLE or PAYLOAD states
            endcase
        end
    end

    // ===================================================================
    // Output Shadow Latch
    always @(posedge clk) begin

        if (rst) begin
            // Clear outputs cleanly on system reset
            out_dmac                <= 48'd0;
            out_smac                <= 48'd0;
            out_ethertype           <= 16'd0;
            out_vlan_id             <= 12'd0;
            out_last_byte_remainder <= 4'd0;
            vlan_data_present       <= 1'b0;
        end

        else if (metadata_valid) begin

            out_dmac      <= dmac_shifter;
            out_smac      <= smac_shifter;
            out_ethertype <= type_shifter;

            if (type_shifter == 16'h8100) begin     // vlan data present
                
                vlan_data_present       <= 1'b1;
                out_vlan_id             <= vlan_shifter[11:0];
                out_last_byte_remainder <= vlan_shifter[15:12];
            end
            else begin
                
                vlan_data_present       <= 1'b0;
                out_vlan_id             <= 12'd0;
                out_last_byte_remainder <= 4'd0;
            end
        end
    end
endmodule