module conv2d_accel #(
    parameter H = 16, W = 16, K = 3,
    parameter DATA_W = 8,                 
    parameter INTERNAL_W = K * DATA_W,    // Core interface width: 24-bit (for K=3)
    parameter ACC_W = 32, ADDR_W = 16
)(
    input  wire clk, rst,
    
    // Write Port (from Testbench/AXI)
    input  wire              wr_en,    
    input  wire [ADDR_W-1:0] wr_addr,  
    input  wire [DATA_W-1:0] wr_data,  // 8-bit write data
    output reg               wr_ready, 
    
    // Read Port (to Testbench/AXI)
    input  wire              rd_en,    
    input  wire [ADDR_W-1:0] rd_addr,  
    output reg  [DATA_W-1:0] rd_data,  // 8-bit read data
    output reg               rd_valid  
);

    localparam OUT_H = H - K + 1;
    localparam OUT_W = W - K + 1;

    wire engine_done; 
    reg start_pulse, counting; 
    reg [31:0] cycle_count;
    reg input_sram_wr_en, kernel_sram_wr_en;
    
    // Internal 24-bit buses (Connecting SRAMs to the Conv Engine)
    wire [INTERNAL_W-1:0] input_rd_data;
    wire [INTERNAL_W-1:0] kernel_rd_data;
    
    
    wire [INTERNAL_W-1:0] output_sram_rd_data; 

    // Wires for Engine Address mapping
    wire [$clog2(H*W)-1:0]         engine_input_rd_addr;
    wire [$clog2(K*K)-1:0]         engine_kernel_rd_addr;
    wire [$clog2(OUT_H*OUT_W)-1:0] engine_output_wr_addr;
    wire                           engine_output_wr_en;
    wire [DATA_W-1:0]              engine_output_wr_data;

    // 1. Input SRAM (Asymmetric: 8-bit write, 24-bit read)
    simple_sram #(.DEPTH(H*W), .WR_W(DATA_W), .K(K)) input_sram (
        .clk(clk), .wr_en(input_sram_wr_en), .wr_addr(wr_addr[$clog2(H*W)-1:0]), 
        .wr_data(wr_data),            // Write 8-bit
        .rd_addr(engine_input_rd_addr), 
        .rd_data(input_rd_data)       // Read 24-bit
    );

    // 2. Kernel SRAM (Asymmetric: 8-bit write, 24-bit read)
    simple_sram #(.DEPTH(K*K), .WR_W(DATA_W), .K(K)) kernel_sram (
        .clk(clk), .wr_en(kernel_sram_wr_en), .wr_addr(wr_addr[$clog2(K*K)-1:0]), 
        .wr_data(wr_data),            // Write 8-bit
        .rd_addr(engine_kernel_rd_addr), 
        .rd_data(kernel_rd_data)      // Read 24-bit
    );

    // 3. Output SRAM 
    simple_sram #(.DEPTH(OUT_H*OUT_W), .WR_W(DATA_W), .K(K)) output_sram (
        .clk(clk), .wr_en(engine_output_wr_en), .wr_addr(engine_output_wr_addr), 
        .wr_data(engine_output_wr_data),      
        .rd_addr(rd_addr[$clog2(OUT_H*OUT_W)-1:0]), 
        .rd_data(output_sram_rd_data) // Outputs 24-bit now
    );

    // 4. PARALLEL CONVOLUTION ENGINE (24-bit Core)
    conv_engine #(
        .H(H), .W(W), .K(K), .PIXEL_W(DATA_W), .ACC_W(ACC_W)
    ) engine (
        .clk(clk), .rst(rst), .start(start_pulse), .done(engine_done),
        .input_rd_addr(engine_input_rd_addr), .input_rd_data(input_rd_data),
        .kernel_rd_addr(engine_kernel_rd_addr), .kernel_rd_data(kernel_rd_data),
        .output_wr_en(engine_output_wr_en), .output_wr_addr(engine_output_wr_addr),
        .output_wr_data(engine_output_wr_data)
    );

    // 5. Address Decoding & Memory Mapped Registers (MMIO)
    always @(posedge clk or posedge rst) begin
        if (rst) begin 
            wr_ready <= 0; start_pulse <= 0; input_sram_wr_en <= 0; kernel_sram_wr_en <= 0; 
        end else begin
            wr_ready <= 0; start_pulse <= 0; input_sram_wr_en <= 0; kernel_sram_wr_en <= 0;
            
            if (wr_en) begin
                wr_ready <= 1; 
                if (wr_addr >= 16'h0000 && wr_addr <= 16'h00FF) 
                    input_sram_wr_en <= 1;  
                else if (wr_addr >= 16'h0100 && wr_addr <= 16'h0108) 
                    kernel_sram_wr_en <= 1; 
                else if (wr_addr == 16'h1000 && wr_data == 8'h01) 
                    start_pulse <= 1;
            end
        end
    end
    
    // 6. Cycle Counter for Performance Measurement
    always @(posedge clk or posedge rst) begin
        if (rst) begin 
            cycle_count <= 0; counting <= 0; 
        end else begin
            if (start_pulse) begin 
                counting <= 1; cycle_count <= 0; 
            end else if (engine_done) begin
                counting <= 0;    
            end
            if (counting) cycle_count <= cycle_count + 1;
        end
    end
    
    // 7. Read Path 
    reg rd_en_d; 
    reg [ADDR_W-1:0] rd_addr_d;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin 
            rd_valid <= 0; rd_en_d <= 0; rd_data <= 0; 
        end else begin
            rd_en_d <= rd_en; 
            rd_addr_d <= rd_addr; 
            rd_valid <= rd_en_d;
            
            if (rd_en_d) begin
                if (rd_addr_d == 16'h1004) 
                    rd_data <= {7'b0, engine_done}; // Status Register
                else if (rd_addr_d == 16'h1008) 
                    rd_data <= cycle_count[7:0];    // Cycle Count Register (lower 8 bits)
                else if (rd_addr_d >= 16'h2000 && rd_addr_d <= 16'h20FF) 
                    rd_data <= output_sram_rd_data[7:0]; 
                else 
                    rd_data <= 8'h00; // Default zero for invalid addresses
            end
        end
    end
endmodule