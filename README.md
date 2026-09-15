# FPGA CNN Handwritten Text Recognition

A CNN-based handwritten character recognition accelerator implemented in Verilog and deployed on the PYNQ-Z2 FPGA using Q8.8 fixed-point arithmetic.

## Overview

This project implements a 62-class handwritten character recognition system using the EMNIST ByClass dataset. The trained CNN is converted to an FPGA-compatible fixed-point implementation and deployed on a Zynq-7000 XC7Z020 FPGA.

**EMNIST → CNN Training → Q8.8 Quantization → Verilog RTL → Vivado → PYNQ-Z2**

## CNN Architecture

32 × 32 × 1 Input
        │
        ▼
Conv1: 3×3, 16 Filters
        │
      ReLU
        │
   MaxPool 2×2
        │
        ▼
Conv2: 3×3, 32 Filters
        │
      ReLU
        │
   MaxPool 2×2
        │
        ▼
Conv3: 3×3, 64 Filters
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

Classes: 0–9, A–Z, a–z

Hardware Platform
Parameter	            Specification
FPGA Board	         PYNQ-Z2
FPGA Device	         Zynq-7000 XC7Z020
Clock	              50 MHz
HDL	                   Verilog
Arithmetic	         Signed Q8.8 / INT16
Memory	              BRAM
Interface	              AXI GPIO

*Results:

Software Model:

Dataset	       EMNIST ByClass
Test Samples	  116,323
Test Accuracy	  82.7893%

->  The 82.7893% accuracy is the measured accuracy of the floating-point software model on the complete EMNIST ByClass test set. A full-dataset FPGA accuracy measurement was not performed.

*FPGA Implementation
Metric	                    Result
RTL Verification	        7/7 Passed
RTL Mismatches	             0
Hardware Prediction	Class   8
Input Checksum	             0xCEA
Result Valid	             1
WNS	                       +1.545 ns
TNS	                       0 ns

*FPGA Resource Utilization:

Resource	    Utilization
LUT	           7.38%
Flip-Flop	      2.33%
BRAM	           78.21%
DSP	           3.64%


*RTL Verification:

The final RTL was verified against golden reference data at every major CNN stage.

Stage	Values Checked	Mismatches
Conv1	14,400	0
Pool1	3,600	0
Conv2	5,408	0
Pool2	1,152	0
Conv3	1,024	0
Dense1	128	0
Output	62	0

*Final verification: 7/7 checkpoints passed with 0 mismatches.

Tools & Technologies:
Python
TensorFlow / Keras
EMNIST ByClass
Verilog HDL
AMD/Xilinx Vivado
PYNQ-Z2
Zynq-7000
AXI GPIO
BRAM
Q8.8 Fixed-Point Arithmetic
