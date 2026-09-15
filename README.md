# FPGA-Based Handwritten Character Recognition Accelerator

**62-class CNN inference engine implemented in Verilog on the PYNQ-Z2 (Xilinx Zynq-7020)**


---

## Overview

A complete software-to-hardware CNN accelerator for handwritten character recognition on the **EMNIST ByClass** dataset (62 classes: `0–9`, `A–Z`, `a–z`).

The network is trained offline in TensorFlow/Keras, quantized to **signed Q8.8 fixed-point**, and implemented as custom **Verilog RTL** on the Zynq-7020 PL. The Zynq PS streams image pixels to the accelerator over **AXI GPIO** and reads back the predicted class, status flags, and an input checksum.

No floating-point hardware, no HLS — the entire datapath is hand-written RTL.

---

## Workflow

```
EMNIST ByClass  →  CNN Training (TF/Keras)  →  Model Export
      →  Q8.8 Quantization  →  Verilog RTL
      →  Vivado Synthesis & Implementation
      →  PYNQ-Z2 Deployment  →  Hardware Inference
```

---

## CNN Architecture

Input: **32 × 32 grayscale**

| Layer   | Configuration       | Output       |
|---------|---------------------|--------------|
| Input   | Grayscale           | 32 × 32 × 1  |
| Conv1   | 3 × 3, 16 filters   | 30 × 30 × 16 |
| Pool1   | 2 × 2, stride 2     | 15 × 15 × 16 |
| Conv2   | 3 × 3, 32 filters   | 13 × 13 × 32 |
| Pool2   | 2 × 2, stride 2     | 6 × 6 × 32   |
| Conv3   | 3 × 3, 64 filters   | 4 × 4 × 64   |
| Flatten | —                   | 1024         |
| Dense1  | 128 neurons + ReLU  | 128          |
| Output  | 62 classes          | 62           |

Classification is completed on-chip with an argmax over the 62 output scores.

---

## Hardware Data Path

```
        Zynq Processing System (PYNQ / Python)
                      |
                   AXI GPIO
                      v
        +------------------------------+
        |     CNN Accelerator (RTL)    |
        |  Conv1 → Pool1 → Conv2       |
        |  → Pool2 → Conv3 → Dense1    |
        |  → Output → Argmax           |
        +------------------------------+
             |                    |
             v                    v
        BRAM (weights,     Output (class,
        biases, acts)      status, checksum)
```

---

## Fixed-Point Datapath

All arithmetic uses **signed 16-bit Q8.8** (8 integer bits, 8 fractional bits).

```
Q8.8 × Q8.8 → wider product → arithmetic right shift by 8 → Q8.8
```

This keeps the full CNN inference free of floating-point resources while preserving adequate numerical range for the quantized weights and activations.

---

## Memory Architecture Optimization

**Problem.** The first activation-memory implementation used asynchronous array reads. Vivado inferred large distributed LUT-based memories instead of dedicated BRAM, causing excessive LUT utilization and blocking implementation.

**Fix.** The activation memory was redesigned around synchronous, BRAM-compatible reads so the large activation buffers map to dedicated block RAM.

**Result.** LUT utilization dropped to **7.38%**, with **78.21%** BRAM — the change that made the full accelerator fit on the Zynq-7020.

---

## Verification

RTL output was compared layer-by-layer against golden-reference data generated from the software model.

| CNN Stage | Values Checked | Mismatches |
|-----------|----------------|------------|
| Conv1     | 14,400         | 0          |
| Pool1     | 3,600          | 0          |
| Conv2     | 5,408          | 0          |
| Pool2     | 1,152          | 0          |
| Conv3     | 1,024          | 0          |
| Dense1    | 128            | 0          |
| Output    | 62             | 0          |

**7/7 checkpoints passed — 0 mismatches.**

Golden reference:

```
Predicted Class : 8
Output[8]       : -26662
Input Checksum  : 0xCEA
Result Valid    : 1
```

---

## Results

### Software Model

| Metric        | Result           |
|---------------|------------------|
| Dataset       | EMNIST ByClass   |
| Test Samples  | 116,323          |
| Test Accuracy | 82.7893%         |

> This is the floating-point software model's accuracy on the full test set. A full-dataset accuracy sweep on the FPGA was not performed.

### FPGA Resource Utilization

| Resource  | Utilization |
|-----------|-------------|
| LUT       | 7.38%       |
| Flip-Flop | 2.33%       |
| BRAM      | 78.21%      |
| DSP       | 3.64%       |

### Timing (50 MHz / 20 ns)

| Metric              | Result     |
|---------------------|------------|
| WNS                 | +1.545 ns  |
| TNS                 | 0 ns       |
| WHS                 | +0.064 ns  |
| THS                 | 0 ns       |
| Pulse Width Slack   | +8.750 ns  |
| **Status**          | **MET**    |

---

## Hardware Validation

Final bitstream deployed and read back on the physical PYNQ-Z2:

| Parameter     | Result     |
|---------------|------------|
| RESULT VALID  | 1          |
| CLASS         | 8          |
| DEBUG STATUS  | 10         |
| CHECKSUM      | 0xCEA      |
| DIAGNOSTIC    | 0x20ACEA   |

Results were stable across repeated reads, confirming the complete host-to-FPGA inference path.


---

## Tools and Technologies

| Category             | Technologies                        |
|----------------------|-------------------------------------|
| Machine Learning     | Python, TensorFlow, Keras           |
| Dataset              | EMNIST ByClass                      |
| Hardware Description | Verilog HDL                         |
| FPGA                 | Xilinx Zynq-7000 (XC7Z020CLG400-1)  |
| Board                | PYNQ-Z2                             |
| Toolchain            | AMD/Xilinx Vivado 2025.1            |
| Arithmetic           | Signed Q8.8 fixed-point / INT16     |
| Memory               | Block RAM (BRAM)                    |
| Host Interface       | AXI GPIO                            |
| Verification         | Verilog testbench + golden reference|

---

## Highlights

- 62-class handwritten character recognition fully in hardware
- Hand-written Verilog CNN inference engine (no HLS)
- Signed Q8.8 fixed-point datapath
- BRAM-based weight, bias, and activation storage
- AXI GPIO integration with the Zynq PS
- Layer-wise RTL verification, 0 mismatches across 7 checkpoints
- 7.38% LUT / 78.21% BRAM utilization
- 50 MHz timing closure, WNS +1.545 ns
- Validated on physical PYNQ-Z2 hardware

---

## Author

**Satyarajsinh Gohil**
B.Tech. Electronics and VLSI Design
