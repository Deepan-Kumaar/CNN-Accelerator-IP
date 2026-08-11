// -------------------------------------------------------------------------------
// -- File       : bram.sv
// -- Author     : Deepan Kumaar Adaikkalam
// -- Created    : 20/07/2026
// -- Edited     : 20/07/2026
// -------------------------------------------------------------------------------
// -- Description: 
// -------------------------------------------------------------------------------
// -- Copyright (c) 2026
// -------------------------------------------------------------------------------

module bram #(
  parameter int WIDTH = 32,
  parameter int DEPTH = 4096,
  parameter int ADDRW = $clog2(DEPTH)
)(
  input  logic                  clk_i,
  input  logic                  en_i, // enable
  input  logic                  we_i, // write enable  
  input  logic [WIDTH/8-1:0]    be_i, // byte enable

  input  logic [ADDRW-1:0]      addr_i, // word address
  input  logic [WIDTH-1:0]      wdata_i, // write data
  output logic [WIDTH-1:0]      rdata_o  // read data
);

  logic [WIDTH-1:0] mem [0:DEPTH-1];

//   read first logic

  always_ff @(posedge clk_i) begin
    if (en_i) begin
      if (we_i) begin
        for (int b = 0; b < WIDTH/8; b++) begin
          if (be_i[b]) mem[addr_i][b*8 +: 8] <= wdata_i[b*8 +: 8];
        end
      end
      rdata_o <= mem[addr_i];
    end
  end

endmodule : bram