# FPGA CNN Handwritten Character Recognition

<p align="center">

**62-Class CNN Accelerator on PYNQ-Z2**

A custom Verilog CNN accelerator for handwritten character recognition using  
**Q8.8 fixed-point arithmetic, BRAM-based memory, and sequential MAC datapaths.**

[![FPGA](https://img.shields.io/badge/FPGA-PYNQ--Z2-blue)](https://www.tulip.com/pynq-z2/)
[![Device](https://img.shields.io/badge/Device-Zynq--7020-blue)](https://www.amd.com/en/products/adaptive-socs-and-fpgas/soc/zynq-7000.html)
[![HDL](https://img.shields.io/badge/HDL-Verilog-orange)](https://www.verilog.com/)
[![Vivado](https://img.shields.io/badge/Vivado-2025.1-red)](https://www.amd.com/en/products/software/adaptive-socs-and-fpgas/vivado.html)
[![Dataset](https://img.shields.io/badge/Dataset-EMNIST%20ByClass-green)](https://www.nist.gov/itl/products-and-services/emnist-dataset)

</p>

---

## Overview

This project implements an end-to-end **FPGA-based handwritten character recognition system** using the **EMNIST ByClass** dataset.

A TensorFlow/Keras CNN is trained in software, converted to an FPGA-compatible representation, quantized to **signed Q8.8 / INT16**, and implemented as custom **Verilog RTL** on the **Xilinx Zynq-7020** FPGA.

EMNIST
   │
   ▼
CNN Training
   │
   ▼
Model Export
   │
   ▼
Q8.8 Quantization
   │
   ▼
Verilog RTL
   │
   ▼
Vivado Implementation
   │
   ▼
PYNQ-Z2
   │
   ▼
Hardware Inference
Key Results
Metric	Result
Character Classes	62
Software Test Accuracy	82.7893%
RTL Verification	7/7 Passed
RTL Mismatches	0
FPGA Clock	50 MHz
LUT Utilization	7.38%
Flip-Flop Utilization	2.33%
BRAM Utilization	78.21%
DSP Utilization	3.64%
Timing WNS	+1.545 ns
Hardware Prediction	Class 8
Hardware Checksum	0xCEA
CNN Architecture

The implemented CNN accepts a 32 × 32 grayscale image and performs inference using fixed-point arithmetic.

32 × 32 × 1 Input
        │
        ▼
Conv1: 3 × 3, 16 Filters
        │
      ReLU
        │
   MaxPool 2 × 2
        │
        ▼
Conv2: 3 × 3, 32 Filters
        │
      ReLU
        │
   MaxPool 2 × 2
        │
        ▼
Conv3: 3 × 3, 64 Filters
        │
      ReLU
        │
        ▼
Flatten: 1024
        │
        ▼
Dense1: 128 + ReLU
        │
        ▼
Output: 62 Classes
        │
        ▼
      Argmax
Layer Dimensions
Layer	Configuration	Output
Input	Grayscale	32 × 32 × 1
Conv1	3 × 3, 16 filters	30 × 30 × 16
Pool1	2 × 2, stride 2	15 × 15 × 16
Conv2	3 × 3, 32 filters	13 × 13 × 32
Pool2	2 × 2, stride 2	6 × 6 × 32
Conv3	3 × 3, 64 filters	4 × 4 × 64
Flatten	—	1024
Dense1	128 neurons + ReLU	128
Output	62 classes	62

Classes: 0–9, A–Z, a–z

FPGA Architecture

The accelerator is implemented using custom Verilog RTL and controlled through the Zynq processing system.

                 ┌─────────────────────────┐
                 │   Zynq Processing       │
                 │   System / PYNQ         │
                 └────────────┬────────────┘
                              │
                              │ AXI
                              ▼
                 ┌─────────────────────────┐
                 │       AXI GPIO          │
                 │  Control + Pixel Input  │
                 └────────────┬────────────┘
                              │
                              ▼
                 ┌─────────────────────────┐
                 │    CNN Accelerator      │
                 │       Verilog RTL       │
                 └────────────┬────────────┘
                              │
                    ┌─────────┴─────────┐
                    │                   │
                    ▼                   ▼
          ┌─────────────────┐   ┌─────────────────┐
          │      BRAM       │   │ Class / Status  │
          │ Weights/Biases  │   │    Checksum     │
          │   Activations   │   └─────────────────┘
          └─────────────────┘
Hardware Platform
Parameter	Specification
Board	PYNQ-Z2
FPGA	Xilinx Zynq-7000
Device	XC7Z020CLG400-1
Clock	50 MHz
HDL	Verilog
Arithmetic	Signed Q8.8 / INT16
Memory	BRAM
Host Interface	AXI GPIO
Development Tool	AMD/Xilinx Vivado 2025.1
RTL Architecture

The final implementation is organized into modular RTL blocks:

rtl/
├── cnn_top.v
├── cnn_gpio_wrapper.v
├── conv_engine_q88.v
├── maxpool_q88.v
├── dense_mac_q88.v
├── mac_q88.v
├── relu_q88.v
└── Bram_weight_ctrl.v
Main Hardware Components
CNN Controller — sequences the complete inference pipeline.
Convolution Engine — performs fixed-point convolution operations.
Max-Pooling Engine — implements 2 × 2 stride-2 pooling.
MAC Unit — performs signed Q8.8 multiply-accumulate operations.
Dense MAC Engine — processes the 1024-element feature vector.
ReLU Unit — performs fixed-point activation.
BRAM Weight Controller — provides synchronized weight and bias access.
GPIO Wrapper — connects the CNN accelerator to the Zynq processing system.

The top-level controller uses nine operational states:

LOAD_INPUT
     ↓
CONV1
     ↓
POOL1
     ↓
CONV2
     ↓
POOL2
     ↓
CONV3
     ↓
DENSE1
     ↓
OUTPUT
     ↓
DEBUG
Fixed-Point Implementation

The hardware datapath uses signed 16-bit Q8.8 arithmetic.

16-bit Q8.8

┌────────────────┬────────────────┐
│  Integer 8-bit │ Fraction 8-bit│
└────────────────┴────────────────┘

For multiplication:

Q8.8 × Q8.8
      │
      ▼
 Wider Product
      │
      ▼
 Arithmetic Right Shift by 8
      │
      ▼
 Q8.8 Result

This allows the CNN to operate without floating-point hardware while keeping the datapath suitable for FPGA implementation.

Memory Optimization

A major implementation challenge was activation-memory inference.

The initial implementation used asynchronous activation-memory reads. Vivado consequently inferred large amounts of distributed LUT-based memory, causing excessive LUT utilization and preventing successful implementation.

The memory architecture was redesigned using:

Synchronous BRAM read interfaces
Dedicated per-array memory access
ram_style = "block" attributes
Synchronized weight and bias access
Explicit memory initialization using $readmemh
Final Memory Result
LUT  Utilization  → 7.38%
BRAM Utilization  → 78.21%

The redesigned architecture moved large activation storage from LUT-based memory into dedicated FPGA BRAM resources.

Software / Hardware Data Ordering

During integration, a critical mismatch was identified between the software tensor layout and the hardware dense-layer memory layout.

Software
HWC Ordering
     │
     │
     │ Custom Export / Reorder
     ▼
Hardware
CHW Ordering

The convolution results were numerically correct, but the flattened feature vector was presented to the dense layer in a different ordering.

A custom export step was introduced to convert the feature vector from HWC to CHW ordering, restoring exact software/hardware alignment.

Verification

The RTL was verified against golden-reference data generated from the software model.

Layer-Wise Verification
CNN Stage	Values Checked	Mismatches
Conv1	14,400	0
Pool1	3,600	0
Conv2	5,408	0
Pool2	1,152	0
Conv3	1,024	0
Dense1	128	0
Output	62	0
Verification Result

7/7 checkpoints passed with 0 mismatches.

Final golden-reference result:

Predicted Class : 8
Output[8]       : -26662
Input Checksum  : 0xCEA
Result Valid    : 1
Software Model Results

The floating-point TensorFlow/Keras model was evaluated on the complete EMNIST ByClass test set.

Metric	Result
Dataset	EMNIST ByClass
Test Samples	116,323
Test Accuracy	82.7893%
Test Loss	0.427682
Number of Classes	62

The 82.7893% value is the measured accuracy of the floating-point software model on the complete EMNIST ByClass test set. A full-dataset FPGA accuracy measurement was not performed.

FPGA Implementation Results
Resource Utilization
Resource	Utilization
LUT	7.38%
Flip-Flop	2.33%
BRAM	78.21%
DSP	3.64%
Timing
Timing Metric	Result
Target Frequency	50 MHz
Clock Period	20 ns
WNS	+1.545 ns
TNS	0 ns
WHS	+0.064 ns
THS	0 ns
Pulse Width Slack	+8.750 ns

All timing constraints were met at the final 50 MHz operating point.

A 100 MHz target was investigated during implementation but did not meet timing due to the critical path and associated fan-out. The final 50 MHz configuration provides positive timing margin.

PYNQ-Z2 Hardware Validation

The final bitstream was deployed on the physical PYNQ-Z2 platform.

Hardware testing produced:

RESULT VALID = 1
CLASS        = 8
DEBUG STATUS = 10
CHECKSUM     = 0xCEA
DIAGNOSTIC   = 0x20ACEA

The result remained stable across repeated hardware reads, confirming correct operation of the complete host-to-FPGA inference path.

Repository Structure
FPGA-CNN-Handwritten-Text-Recognition/
│
├── python/
│   ├── train.py
│   ├── model.py
│   ├── data_loader.py
│   └── evaluate.py
│
├── rtl/
│   ├── cnn_top.v
│   ├── cnn_gpio_wrapper.v
│   ├── conv_engine_q88.v
│   ├── maxpool_q88.v
│   ├── dense_mac_q88.v
│   ├── mac_q88.v
│   ├── relu_q88.v
│   └── Bram_weight_ctrl.v
│
├── testbench/
│   ├── cnn_top_tb.v
│   └── cnn_checksum_tb.v
│
└── README.md
Tools & Technologies
Machine Learning
Python
TensorFlow / Keras
EMNIST ByClass
Hardware Design
Verilog HDL
Fixed-Point Q8.8 Arithmetic
BRAM
Sequential MAC Datapaths
RTL Verification
FPGA Development
AMD/Xilinx Vivado
Xilinx Zynq-7000
PYNQ-Z2
AXI GPIO
Project Highlights
62-class EMNIST handwritten character recognition
Custom CNN accelerator implemented in Verilog RTL
Signed Q8.8 / INT16 fixed-point datapath
BRAM-based weight and activation storage
Sequential MAC architecture
Nine-state CNN inference controller
Layer-wise golden-reference verification
7/7 verification checkpoints passed
0 RTL mismatches
50 MHz timing closure
+1.545 ns WNS
7.38% LUT utilization
Physical PYNQ-Z2 hardware validation
Future Work
Add a hardware cycle counter for exact inference-latency measurement.
Evaluate the quantized FPGA implementation across the complete EMNIST test set.
Replace AXI GPIO image transfer with higher-throughput AXI/DMA interfaces.
Explore additional MAC parallelism for higher inference throughput.
Optimize BRAM organization and reduce memory footprint.
Investigate quantization-aware training for improved fixed-point accuracy.
Author

Satyarajsinh Gohil

B.Tech. Electronics and VLSI Design
Dhirubhai Ambani University (DAU)
