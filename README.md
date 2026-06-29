# CNN Convolution Accelerator - Team Project
Target: ZCU104 (XCZU7EV-2FFVC1156) - Synthesis only
## Project Overview

Convolutional Neural Networks (CNNs) are the backbone of modern image recognition. The key operation is 2D convolution: sliding a small filter (kernel) over an input image and computing weighted sums. This operation is computationally expensive, requiring millions of multiply-accumulate (MAC) operations. This project aims to design a dedicated hardware accelerator on an FPGA to perform this operation efficiently, verified against a custom Python-based golden reference. This project was completed by a team of four members.
## Project Goals
- Understand 2D convolution and its role in CNNs
- Implement 2D convolution in Python from scratch (no library convolution functions)
- Understand quantization: converting floating-point model weights to 8-bit integers
- Build a memory-mapped IP wrapper with SRAMs and control/status registers
- Verify hardware against the software golden reference using $readmemh
- Analyze FPGA resource usage and performance
### Background

**1. 2D Convolution & Memory Layout**
The core operation slides a $K \times K$ kernel over an $H \times W$ input feature map. For a 3x3 kernel, calculating a single output pixel requires 9 multiplications and 8 additions. Hardware stores these 2D arrays in 1D linear memory using row-major order, requiring precise address calculation logic (`Address = r * num_cols + c`).

**2. Quantization**
While neural networks are trained using 32-bit floats, hardware prefers 8-bit integers. 8-bit integers drastically reduce memory bandwidth and multiplier size with minimal accuracy loss during inference. This project converts FP32 weights and activations to INT8 using scale-based quantization.

## Software Implementation (Python)

The software half of the project is responsible for data preparation and golden reference generation, strictly without using library convolution functions.

* `conv2d.py`: Implements a 2D valid convolution from scratch using nested loops.
* `prepare_data.py`: A complete pipeline that:
    1. Loads a pre-trained MNIST CNN model.
    2. Extracts floating-point weights from the first convolutional layer (3x3 kernel).
    3. Quantizes the weights and input image to 8-bit signed integers (-128 to 127).
    4. Computes the integer convolution to serve as the golden reference.
    5. Generates `.txt` hex files for Verilog `$readmemh` integration (`input_feature_map.txt`, `kernel.txt`, `expected_output.txt`).

## Hardware Implementation & My Contributions

As the Hardware Developer for this team, I was fully responsible for the RTL design and architecture optimization:

### 1. Architecture Design
* **Baseline Accelerator:** Implemented a robust serial MAC architecture based on an FSM controller and memory-mapped SRAMs.
* **K-Multiplier Architecture (Extension):** Upgraded the design to a Partially Parallel Architecture using $K$ multipliers (3 multipliers for a 3x3 kernel). This reduces the computation cycles about 3 times by fetching and calculating multiple pixels simultaneously.

### 2. Verification & Memory-Mapped IO
Designed the `conv2d_accel.v` wrapper to provide a memory-mapped interface, allowing seamless read/write access to internal SRAMs and Control/Status Registers (CSR). Functional verification was successfully passed by comparing FPGA outputs against the Python hex files in `tb_conv2d_accel.v`.

## Block Diagram
<img width="1287" height="706" alt="image" src="https://github.com/user-attachments/assets/5ea788b2-c275-4f31-99c8-d3b3ec55e89e" />

## Convolution Engine FSM State Diagram
<img width="947" height="402" alt="image" src="https://github.com/user-attachments/assets/e996c566-0dae-4987-85a3-ab8c87ac255a" />

## Performance Evaluation: Baseline vs. K-Multiplier Architecture

The transition from a Baseline Serial MAC to a Partially Parallel MAC (K-Multiplier) architecture demonstrates a classic **area-time trade-off** in hardware design for CNN convolution. The table below highlights the drastic reduction in execution time achieved at the cost of higher logic utilization.

### Performance Comparison

| Metric | Baseline (Serial) | Partially Parallel (3 MACs) | Improvement |
| :--- | :--- | :--- | :--- |
| **Compute Cycles / Pixel** | 9 Cycles | 3 Cycles | 3.00× Faster |
| **Total Execution Cycles** | 3724 Cycles | 1372 Cycles | 2.71× Faster |
| **Execution Latency** | 37.24 µs | 13.73 µs | 2.71× Lower |
| **Throughput (MMAC/s)** | 47.37 MMAC/s | 128.57 MMAC/s | 2.71× Higher |
| **LUT Utilization** | 229 | 424 | 85.15% Increase |

### Evaluation & Key Observations

* **Significant Speedup:** Processing an entire kernel row simultaneously reduced the computation time per output pixel from 9 to 3 cycles, translating to an impressive overall system speedup of **2.71×**.
* **The Area-Time Trade-off:** Achieving this throughput required integrating extra multipliers and an adder tree, causing LUT utilization to increase by **85.15%**. In real-world chip design, this area increase is a highly acceptable price to pay for nearly tripling the processing speed.
* **Amdahl’s Law Limitation:** While the core math operations are exactly 3× faster, the overall system speedup caps at 2.71×. This occurs because the static overhead of non-math operations—such as FSM state transitions, memory read latency (FETCH), and writing results (OUTPUT)—remains constant. 

**Conclusion:** The parallel multiplier extension effectively optimizes hardware bottlenecks, proving that scaling MAC units is a highly successful strategy to increase CNN accelerator throughput.
## Repository Structure

```text
├── src/
│   ├── simple_sram.v        # Configurable SRAM module
│   ├── conv_engine.v        # FSM-based core convolution engine
│   └── conv2d_accel.v       # Memory-mapped IP Wrapper
├── tb/
│   └── tb_conv2d_accel.v    # Integration testbench
├── python/
│   ├── conv2d.py            # Custom 2D convolution implementation
│   └── prepare_data.py      # Quantization & Hex generation script
└── timing.xdc               # Timing constraints for Vivado synthesis
