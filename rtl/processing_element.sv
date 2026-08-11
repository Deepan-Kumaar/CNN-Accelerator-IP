// -------------------------------------------------------------------------------
// -- File       : processing_element.sv
// -- Author     : Deepan Kumaar Adaikkalam
// -- Edited     : 14/07/2026
// -------------------------------------------------------------------------------
// -- Description: This module implements a processing element that performs multiply 
//    and accumulate operation. It takes in data and weight as inputs, multiplies them, 
//    and accumulates the result in an accumulator register. The accumulator can 
// be cleared or reset based on control signals.
// -------------------------------------------------------------------------------
// -- Copyright (c) 2026
// -------------------------------------------------------------------------------


module processing_element #(
    parameter int DATA_WIDTH=8, parameter  int ACC_WIDTH=32
) (
    input logic clk_i,
    input logic rst_ni,
    input logic en_i,
    input logic clear_i,
    
    input logic signed [DATA_WIDTH-1:0] data_i,
    input logic signed [DATA_WIDTH-1:0] weight_i,

    output logic signed [ACC_WIDTH-1:0] acc_o


);

logic signed [ACC_WIDTH-1:0] acc_r;

assign acc_o = acc_r;

always_ff @(posedge clk_i or negedge rst_ni) 
begin
    if (!rst_ni) begin
        acc_r <= '0;
    end else if (clear_i) begin
        acc_r <= '0;
    end else if (en_i) begin
        acc_r <= acc_r + (data_i * weight_i);//Mutiply and add the values
    end

end



    
endmodule