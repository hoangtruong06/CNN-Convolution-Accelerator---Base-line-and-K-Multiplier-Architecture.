module simple_sram #(
    parameter DEPTH = 256,            // 256 for 16x16 input image
    parameter WR_W = 8,               // WRITE Port: 8-bit (For Testbench data loading)
    parameter K = 3,                  // Parallelism factor (Processing 3 pixels at once)
    parameter RD_W = K * WR_W         // READ Port: 24-bit (For Conv Engine to fetch 3 bytes)
)(
    input  wire clk,
    input  wire wr_en,
    input  wire [$clog2(DEPTH)-1:0] wr_addr,
    input  wire [WR_W-1:0]          wr_data,  // 8-bit input data
    
    input  wire [$clog2(DEPTH)-1:0] rd_addr,
    output reg  [RD_W-1:0]          rd_data   // 24-bit output data
);

    reg [WR_W-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        // Write flow: Standard 8-bit single write
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
        
        // Read flow: Fetch & concatenate 3 consecutive memory cells 
        // (Includes safety boundary checks to prevent out-of-bounds reads)
        rd_data[7:0]   <= (rd_addr < DEPTH)     ? mem[rd_addr]   : 8'd0;
        rd_data[15:8]  <= (rd_addr + 1 < DEPTH) ? mem[rd_addr+1] : 8'd0;
        rd_data[23:16] <= (rd_addr + 2 < DEPTH) ? mem[rd_addr+2] : 8'd0;
    end

endmodule