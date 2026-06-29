module simple_sram #(
    parameter DEPTH = 64,  // Total number of memory cells in the SRAM 
    parameter DATA_W = 8   // Width of each memory cell (8-bit data width) 
)(
    input  wire clk,       // System clock 
    input  wire wr_en,     // Write Enable signal 
    
    // Write Port 
    input  wire [$clog2(DEPTH)-1:0] wr_addr, // Write address 
    input  wire [DATA_W-1:0]        wr_data, // 8-bit write data 
    
    // Read Port 
    input  wire [$clog2(DEPTH)-1:0] rd_addr, // Read address 
    output reg  [DATA_W-1:0]        rd_data  // 8-bit read data output 
);

    // Memory array declaration (Linear memory)
    reg [DATA_W-1:0] mem [0:DEPTH-1];
    
    always @(posedge clk) begin 
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end    
        rd_data <= mem[rd_addr]; 
    end

endmodule