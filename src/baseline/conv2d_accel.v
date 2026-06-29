module conv2d_accel #(
    parameter H = 16,           
    parameter W = 16,
    parameter K = 3,
    parameter DATA_W = 8,
    parameter ACC_W = 32,
    parameter ADDR_W = 16
)(
    input  wire clk,
    input  wire rst,
    
    // Memory mapped external bus interface
    input  wire              wr_en,
    input  wire [ADDR_W-1:0] wr_addr,
    input  wire [DATA_W-1:0] wr_data,
    output reg               wr_ready,
    
    input  wire              rd_en,
    input  wire [ADDR_W-1:0] rd_addr,
    output reg  [DATA_W-1:0] rd_data,
    output reg               rd_valid
);

    localparam OUT_H = H - K + 1;
    localparam OUT_W = W - K + 1;

    // --- INTERNAL CONNECTION SIGNALS ---
    wire engine_done;
    reg  start_pulse;
    reg  [31:0] cycle_count;
    reg  counting;

    
    reg input_sram_wr_en;
    reg kernel_sram_wr_en;
    wire [DATA_W-1:0] input_rd_data;
    wire [DATA_W-1:0] kernel_rd_data;

    // Intermediate wires between Wrapper and Conv Engine
    wire [$clog2(H*W)-1:0] engine_input_rd_addr;
    wire [$clog2(K*K)-1:0] engine_kernel_rd_addr;
    wire engine_output_wr_en;
    wire [$clog2(OUT_H*OUT_W)-1:0] engine_output_wr_addr;
    wire [DATA_W-1:0] engine_output_wr_data;
    wire [DATA_W-1:0] output_sram_rd_data;

    // ==========================================
    // INSTANTIATION: Assemble the 3 Memory blocks (SRAM)
    // ==========================================

    // 1. Instantiate Input SRAM
    wire [$clog2(H*W)-1:0] input_actual_wr_addr = wr_addr[$clog2(H*W)-1:0];
    simple_sram #(.DEPTH(H*W), .DATA_W(DATA_W)) input_sram (
        .clk(clk), 
        .wr_en(input_sram_wr_en), 
        .wr_addr(input_actual_wr_addr), 
        .wr_data(wr_data),            
        .rd_addr(engine_input_rd_addr), 
        .rd_data(input_rd_data)
    );

    // 2. Instantiate Kernel SRAM
    wire [$clog2(K*K)-1:0] kernel_actual_wr_addr = wr_addr[$clog2(K*K)-1:0];
    simple_sram #(.DEPTH(K*K), .DATA_W(DATA_W)) kernel_sram (
        .clk(clk), 
        .wr_en(kernel_sram_wr_en), 
        .wr_addr(kernel_actual_wr_addr), 
        .wr_data(wr_data),               
        .rd_addr(engine_kernel_rd_addr), 
        .rd_data(kernel_rd_data)
    );

    // 3. Instantiate Output SRAM
    wire [$clog2(OUT_H*OUT_W)-1:0] output_actual_rd_addr = rd_addr[$clog2(OUT_H*OUT_W)-1:0];
    simple_sram #(.DEPTH(OUT_H*OUT_W), .DATA_W(DATA_W)) output_sram (
        .clk(clk), 
        .wr_en(engine_output_wr_en), 
        .wr_addr(engine_output_wr_addr), 
        .wr_data(engine_output_wr_data),     
        .rd_addr(output_actual_rd_addr), 
        .rd_data(output_sram_rd_data)
    );

    // ==========================================
    // INSTANTIATION: Assemble the Brain (Conv Engine)
    // ==========================================
    conv_engine #(
        .H(H), .W(W), .K(K), .DATA_W(DATA_W), .ACC_W(ACC_W)
    ) engine (
        .clk(clk), .rst(rst), .start(start_pulse), .done(engine_done),
        .input_rd_addr(engine_input_rd_addr), .input_rd_data(input_rd_data),
        .kernel_rd_addr(engine_kernel_rd_addr), .kernel_rd_data(kernel_rd_data),
        .output_wr_en(engine_output_wr_en), .output_wr_addr(engine_output_wr_addr),
        .output_wr_data(engine_output_wr_data)
    );

    // ==========================================
    // LOGIC 1: Write Path & Address Decoding
    // ==========================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ready <= 0;
            start_pulse <= 0;
            input_sram_wr_en <= 0;
            kernel_sram_wr_en <= 0;
        end else begin
            // Pulse: Auto-clear after 1 cycle
            wr_ready <= 0;
            start_pulse <= 0;
            input_sram_wr_en <= 0;
            kernel_sram_wr_en <= 0;
            
            if (wr_en) begin
                wr_ready <= 1;
                
                // Address Decoding
                if (wr_addr >= 16'h0000 && wr_addr <= 16'h00FF) begin
                    input_sram_wr_en <= 1;  //Enable write signal
                end
                else if (wr_addr >= 16'h0100 && wr_addr <= 16'h0108) begin
                    kernel_sram_wr_en <= 1; 
                end
                else if (wr_addr == 16'h1000) begin
                    if (wr_data == 8'h01) start_pulse <= 1;
                end
            end
        end
    end
    
    // ==========================================
    // LOGIC 2: Cycle Counter
    // ==========================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cycle_count <= 0;
            counting <= 0;
        end else begin
            if (start_pulse) begin
                counting <= 1;
                cycle_count <= 0; 
            end else if (engine_done) begin
                counting <= 0;
            end
            
            if (counting) cycle_count <= cycle_count + 1;
        end
    end
    
    // ==========================================
    // LOGIC 3: Read Path & 1-Cycle Delay
    // ==========================================
    reg rd_en_delayed;
    reg [ADDR_W-1:0] rd_addr_delayed;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_valid <= 0;
            rd_en_delayed <= 0; 
            rd_data <= 0;
        end else begin
            rd_en_delayed <= rd_en;
            rd_addr_delayed <= rd_addr;
            rd_valid <= rd_en_delayed;
            
            if (rd_en_delayed) begin
                if (rd_addr_delayed == 16'h1004) begin
                    rd_data <= {7'b0, engine_done};
                end
                else if (rd_addr_delayed == 16'h1008) begin
                    rd_data <= cycle_count[7:0];
                end
                else if (rd_addr_delayed >= 16'h2000 && rd_addr_delayed <= 16'h20FF) begin
                    rd_data <= output_sram_rd_data;
                end else begin
                    rd_data <= 8'h00;
                end
            end
        end
    end

endmodule