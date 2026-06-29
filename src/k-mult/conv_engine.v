module conv_engine #(
    parameter H = 16,
    parameter W = 16,
    parameter K = 3,
    parameter PIXEL_W = 8,
    parameter DATA_W = K * PIXEL_W, // 24-bit input from SRAM
    parameter ACC_W = 32
)(
    input  wire clk, rst, start,
    
    output reg  [$clog2(H*W)-1:0] input_rd_addr,
    input  wire [DATA_W-1:0]      input_rd_data,  
    
    output reg  [$clog2(K*K)-1:0] kernel_rd_addr,
    input  wire [DATA_W-1:0]      kernel_rd_data, 
    
    output reg  output_wr_en,
    output reg  [$clog2((H-K+1)*(W-K+1))-1:0] output_wr_addr,
    output reg  signed [PIXEL_W-1:0] output_wr_data, 
    
    output reg  done
);

    localparam OUT_H = H - K + 1;
    localparam OUT_W = W - K + 1;
    
    localparam IDLE=0, FETCH=1, MAC=2, OUTPUT=3, DONE=4;
    reg [2:0] state, next_state;
    
    reg [$clog2(OUT_H)-1:0] out_row;
    reg [$clog2(OUT_W)-1:0] out_col;
    reg [$clog2(K)-1:0]     ki;
    reg signed [ACC_W-1:0] acc;

    // --- PARALLEL DATAPATH (K=3 Multipliers) ---
    wire signed [PIXEL_W-1:0] in_p [0:K-1];
    wire signed [PIXEL_W-1:0] k_p  [0:K-1];
    wire signed [PIXEL_W*2-1:0] mult [0:K-1];
    wire signed [ACC_W-1:0] adder_tree_sum;

    genvar i;
    generate
        for (i = 0; i < K; i = i + 1) begin : split_bus
            assign in_p[i] = input_rd_data[i*PIXEL_W +: PIXEL_W];
            assign k_p[i]  = kernel_rd_data[i*PIXEL_W +: PIXEL_W];
            assign mult[i] = in_p[i] * k_p[i];
        end
    endgenerate

    assign adder_tree_sum = mult[0] + mult[1] + mult[2]; // Calculating 3 pixels at the same time

    // --- FSM ---
    always @(posedge clk or posedge rst) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE:   if (start) next_state = FETCH;
            FETCH:  next_state = MAC;
            MAC:    if (ki == K-1) next_state = OUTPUT; else next_state = FETCH;
            OUTPUT: if (out_row == OUT_H-1 && out_col == OUT_W-1) next_state = DONE; else next_state = FETCH;
            DONE:   next_state = DONE;
        endcase
    end

    always @(*) begin
        input_rd_addr  = (out_row + ki) * W + out_col; 
        kernel_rd_addr = ki * K; 
    end 
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            out_row <= 0; out_col <= 0; ki <= 0; acc <= 0; done <= 0; output_wr_en <= 0;
        end else begin
            output_wr_en <= 0; 
            case (state)
                IDLE: begin out_row <= 0; out_col <= 0; ki <= 0; acc <= 0; done <= 0; end
                MAC: begin
                    acc <= acc + adder_tree_sum; 
                    if (ki == K-1) ki <= 0; else ki <= ki + 1;
                end
                OUTPUT: begin
                    output_wr_en <= 1; output_wr_addr <= out_row * OUT_W + out_col; output_wr_data <= acc[7:0];
                    acc <= 0;
                    if (out_col == OUT_W-1) begin out_col <= 0; out_row <= out_row + 1; end else out_col <= out_col + 1;
                end
                DONE: done <= 1;
            endcase
        end
    end
endmodule