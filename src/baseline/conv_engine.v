module conv_engine #(
    parameter H = 16,           // Input Height
    parameter W = 16,           // Input Width
    parameter K = 3,           // Kernel Size
    parameter DATA_W = 8,      // Data width
    parameter ACC_W = 32       // Accumulator width 
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    
    // Input SRAM Interface (Read)
    output reg  [$clog2(H*W)-1:0] input_rd_addr,
    input  wire signed [DATA_W-1:0] input_rd_data,
    
    // Kernel SRAM Interface (Read)
    output reg  [$clog2(K*K)-1:0] kernel_rd_addr,
    input  wire signed [DATA_W-1:0] kernel_rd_data,
    
    // Output SRAM Interface (Write)
    output reg  output_wr_en,
    output reg  [$clog2((H-K+1)*(W-K+1))-1:0] output_wr_addr,
    output reg  signed [DATA_W-1:0] output_wr_data,
    
    output reg  done
);
    // Output Dimensions
    localparam OUT_H = H - K + 1;
    localparam OUT_W = W - K + 1;
   
    // 5 FSM States
    localparam IDLE   = 3'd0,
               FETCH  = 3'd1,
               MAC    = 3'd2,
               OUTPUT = 3'd3,
               DONE   = 3'd4;
               
    reg [2:0] state, next_state;
    
    // Coordinate counters
    reg [$clog2(OUT_H)-1:0] out_row;
    reg [$clog2(OUT_W)-1:0] out_col;
    reg [$clog2(K)-1:0] ki, kj;
    
    // 32-bit signed Accumulator
    reg signed [ACC_W-1:0] acc;

    // --------------------------------------------------------
    // FSM BLOCK 1: State update (Sequential)
    // --------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    // --------------------------------------------------------
    // FSM BLOCK 2: Next state logic (Combinational)
    // --------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:   if (start) next_state = FETCH;
            
            FETCH:  next_state = MAC; // Must go to MAC to wait for 1-cycle SRAM delay
            
            MAC: begin
                // If kernel traversal is done -> Go write result
                if (ki == K-1 && kj == K-1) next_state = OUTPUT;
                // If not -> Go back to FETCH for next kernel pixel
                else next_state = FETCH; 
            end
            
            OUTPUT: begin
                // If the entire Output matrix is computed -> Done
                if (out_row == OUT_H-1 && out_col == OUT_W-1) next_state = DONE;
                // If not -> Compute the next output pixel
                else next_state = FETCH;
            end
            
            DONE:   next_state = DONE; 
        endcase
    end

    // --------------------------------------------------------
    // FSM BLOCK 3: Datapath - Actions in each state
    // --------------------------------------------------------
    // --------------------------------------------------------
    // Combinational logic for continuous address generation 
    // --------------------------------------------------------
    always @(*) begin
        input_rd_addr  = (out_row + ki) * W + (out_col + kj);
        kernel_rd_addr = ki * K + kj;
    end 
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            out_row <= 0; out_col <= 0;
            ki <= 0; kj <= 0;
            acc <= 0; done <= 0;
            output_wr_en <= 0;
        end else begin
            // Default disable write signal to prevent garbage data
            output_wr_en <= 0; 
            
            case (state)
                IDLE: begin
                    out_row <= 0; out_col <= 0;
                    ki <= 0; kj <= 0;
                    acc <= 0; done <= 0;
                end
                
                FETCH: begin
                    // Waiting state
                end
                
                MAC: begin
                    // Data arrived from SRAM, perform MAC
                    acc <= acc + (input_rd_data * kernel_rd_data);
                    // Logic to increment Kernel counters (ki, kj)
                    if (kj == K-1) begin
                        kj <= 0;
                        if (ki == K-1) ki <= 0;
                        else ki <= ki + 1;
                    end else begin
                        kj <= kj + 1;
                    end
                end
                
                OUTPUT: begin
                    // Truncate to lower 8-bits and write to SRAM
                    output_wr_en   <= 1;
                    output_wr_addr <= out_row * OUT_W + out_col;
                    output_wr_data <= acc[7:0];
                    // Reset acc for the next pixel
                    acc <= 0;
                    // Logic to increment Output counters (out_row, out_col)
                    if (out_col == OUT_W-1) begin
                        out_col <= 0;
                        out_row <= out_row + 1;
                    end else begin
                        out_col <= out_col + 1;
                    end
                end
                
                DONE: begin
                    done <= 1; // Set done flag
                end
            endcase
        end
    end
endmodule