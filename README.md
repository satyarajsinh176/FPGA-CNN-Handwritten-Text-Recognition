<div align="center">

# FPGA-Based Handwritten Character Recognition Accelerator

### Hardware Implementation of a 62-Class Convolutional Neural Network on the PYNQ-Z2 FPGA

</div>

## Overview

This project implements an **FPGA-based handwritten character recognition accelerator** on the **PYNQ-Z2** using a custom **Verilog CNN inference architecture**.

The system uses the **EMNIST ByClass** dataset containing **62 character classes (0–9, A–Z, a–z)**. The CNN is trained offline using **TensorFlow/Keras**, converted into an FPGA-compatible inference model, quantized to **signed Q8.8 fixed-point format**, and implemented using custom **Verilog HDL** on the Xilinx **Zynq-7020** FPGA.

The complete development flow covers neural network training, model export, fixed-point quantization, RTL implementation, Vivado synthesis and implementation, simulation-based verification, and physical PYNQ-Z2 hardware validation.

---

## System Workflow

```text
EMNIST ByClass
      |
      v
CNN Training
      |
      v
Model Export
      |
      v
Q8.8 Quantization
      |
      v
Verilog RTL
      |
      v
Vivado Synthesis & Implementation
      |
      v
PYNQ-Z2 Deployment
      |
      v
FPGA Hardware Inference

The accelerator receives image pixels through the Zynq processing system using AXI GPIO, performs the complete CNN inference in hardware, and returns the predicted class together with hardware status and input checksum information.

CNN Architecture

The implemented CNN accepts a 32 × 32 grayscale image and consists of three convolutional stages followed by a fully connected classifier.

32 × 32 × 1 Input
       |
       v
Conv1: 3 × 3, 16 Filters
       |
     ReLU
       |
MaxPool: 2 × 2
       |
       v
Conv2: 3 × 3, 32 Filters
       |
     ReLU
       |
MaxPool: 2 × 2
       |
       v
Conv3: 3 × 3, 64 Filters
       |
     ReLU
       |
       v
Flatten: 1024
       |
       v
Dense1: 128 + ReLU
       |
       v
Output: 62 Classes
       |
       v
Argmax
Layer Configuration
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

The accelerator is implemented using custom Verilog RTL and integrated with the Zynq processing system through AXI GPIO.

                 +---------------------------+
                 |   Zynq Processing System  |
                 |        PYNQ / Python      |
                 +-------------+-------------+
                               |
                               | AXI GPIO
                               v
                 +---------------------------+
                 |     CNN Accelerator       |
                 |        Verilog RTL        |
                 |                           |
                 | Conv1 → Pool1             |
                 | Conv2 → Pool2             |
                 | Conv3 → Dense1            |
                 | Output → Argmax           |
                 +-------------+-------------+
                               |
                    +----------+----------+
                    |                     |
                    v                     v
             +-------------+       +-------------+
             |    BRAM     |       |   Output    |
             |             |       |             |
             | Weights     |       | Class       |
             | Biases      |       | Status      |
             | Activations |       | Checksum    |
             +-------------+       +-------------+
Hardware Platform
Parameter	Specification
FPGA Board	PYNQ-Z2
FPGA Family	Xilinx Zynq-7000
FPGA Device	XC7Z020CLG400-1
Clock Frequency	50 MHz
HDL	Verilog HDL
Arithmetic	Signed Q8.8 / INT16
Memory	Block RAM (BRAM)
Host Interface	AXI GPIO
FPGA Toolchain	AMD/Xilinx Vivado 2025.1
RTL Architecture

The hardware accelerator is divided into modular RTL components.

rtl/
│
├── cnn_top.v
├── cnn_gpio_wrapper.v
├── conv_engine_q88.v
├── maxpool_q88.v
├── dense_mac_q88.v
├── mac_q88.v
├── relu_q88.v
└── Bram_weight_ctrl.v
Hardware Modules
Module	Description
cnn_top.v	Top-level CNN controller and datapath
cnn_gpio_wrapper.v	PYNQ / AXI GPIO interface
conv_engine_q88.v	Fixed-point convolution engine
maxpool_q88.v	2 × 2 max-pooling engine
dense_mac_q88.v	Dense-layer MAC engine
mac_q88.v	Fixed-point multiply-accumulate unit
relu_q88.v	ReLU activation unit
Bram_weight_ctrl.v	Weight and bias BRAM controller

The top-level controller uses nine operational states:

LOAD_INPUT
     |
     v
CONV1
     |
     v
POOL1
     |
     v
CONV2
     |
     v
POOL2
     |
     v
CONV3
     |
     v
DENSE1
     |
     v
OUTPUT
     |
     v
DEBUG
Fixed-Point Implementation

The FPGA datapath uses signed 16-bit Q8.8 fixed-point arithmetic.

16-bit Q8.8

+----------------+----------------+
| Integer: 8 bit | Fraction: 8 bit|
+----------------+----------------+

The multiplication datapath performs fixed-point scaling after multiplication:

Q8.8 × Q8.8
      |
      v
Wider Product
      |
      v
Arithmetic Right Shift by 8
      |
      v
Q8.8 Result

This enables the CNN to perform inference without floating-point hardware while maintaining the required numerical representation.

Memory Optimization

Memory architecture was one of the major implementation challenges.

The initial activation-memory implementation used asynchronous array reads, which caused Vivado to infer large distributed LUT-based memories instead of dedicated BRAM.

This resulted in excessive LUT utilization and prevented successful implementation.

The final architecture was redesigned using:

Synchronous BRAM read interfaces
Dedicated memory access blocks
ram_style = "block" attributes
Synchronized weight and bias access
Explicit $readmemh memory initialization
Final Memory Utilization
Resource	Utilization
LUT	7.38%
BRAM	78.21%

The redesigned memory architecture moved large activation storage from LUT-based memory into dedicated FPGA BRAM resources.

Software / Hardware Data Ordering

During integration, a mismatch was identified between the software tensor layout and the hardware dense-layer memory layout.

Software Tensor
      |
      v
 HWC Ordering
      |
      |
      | Custom Export / Reorder
      |
      v
 CHW Ordering
      |
      v
Hardware Dense Layer

The convolution outputs were numerically correct, but the flattened feature vector was presented to the dense layer in a different ordering.

A custom export step was introduced to convert the feature vector from HWC to CHW ordering, restoring exact software and hardware alignment.

RTL Verification

The RTL implementation was verified against golden-reference data generated from the software model.

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

The 82.7893% accuracy represents the measured performance of the floating-point software model on the complete EMNIST ByClass test set.

A full-dataset FPGA accuracy measurement was not performed.

FPGA Implementation Results
Resource Utilization
FPGA Resource	Utilization
LUT	7.38%
Flip-Flop	2.33%
BRAM	78.21%
DSP	3.64%
Timing Analysis
Timing Metric	Result
Target Frequency	50 MHz
Clock Period	20 ns
WNS	+1.545 ns
TNS	0 ns
WHS	+0.064 ns
THS	0 ns
Pulse Width Slack	+8.750 ns

All timing constraints were successfully met at the final 50 MHz operating point.

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

Project Highlights
62-class handwritten character recognition
Custom CNN accelerator implemented using Verilog RTL
Signed Q8.8 / INT16 fixed-point datapath
BRAM-based weight, bias, and activation storage
Sequential MAC architecture
Nine-state CNN inference controller
HWC-to-CHW hardware data-order correction
Layer-wise golden-reference verification
7/7 verification checkpoints passed
0 RTL mismatches
50 MHz timing closure
+1.545 ns WNS
7.38% LUT utilization
Physical PYNQ-Z2 hardware validation

Tools and Technologies
Category	Technologies
Machine Learning	Python, TensorFlow, Keras
Dataset	EMNIST ByClass
Hardware Description	Verilog HDL
FPGA	Xilinx Zynq-7000
Development Board	PYNQ-Z2
FPGA Toolchain	AMD/Xilinx Vivado 2025.1
Arithmetic	Q8.8 Fixed-Point / INT16
Memory	BRAM
Interface	AXI GPIO
Verification	Verilog Testbench, Golden Reference

Author

Satyarajsinh Gohil

B.Tech. Electronics and VLSI Design
Dhirubhai Ambani University (DAU)
