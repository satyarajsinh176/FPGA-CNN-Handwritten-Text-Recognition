# FPGA-Based CNN Accelerator for Handwritten Text Recognition

A hardware-accelerated Convolutional Neural Network (CNN) implemented in Verilog for FPGA-based handwritten text recognition.

## Overview

This project focuses on implementing CNN inference using custom RTL hardware modules on a Xilinx Zynq-7020 FPGA platform.

The accelerator uses fixed-point arithmetic and dedicated hardware datapaths to perform neural network computations efficiently.

## Key Features

- Custom Verilog RTL implementation of CNN computation
- Fixed-point Q8.8 arithmetic
- Sequential MAC-based computation
- BRAM-based weight storage
- Convolution and activation processing
- ReLU activation
- Max-pooling
- Fully connected layer
- Python-based reference model and verification
- Hardware-oriented layer-by-layer verification

## Hardware Architecture

The CNN accelerator is composed of dedicated RTL modules for computation, memory management, activation functions, and pooling.

```text
Input Image
     │
     ▼
Convolution
     │
     ▼
ReLU
     │
     ▼
Max Pooling
     │
     ▼
Convolution
     │
     ▼
ReLU
     │
     ▼
Max Pooling
     │
     ▼
Convolution
     │
     ▼
ReLU
     │
     ▼
Fully Connected
     │
     ▼
Prediction

RTL Modules
Module	                  Description
cnn_top.v	           Top-level CNN accelerator
conv_engine_q88.v	 Fixed-point convolution engine
dense_mac_q88.v	 MAC-based dense-layer computation
mac_q88.v            Fixed-point multiply-accumulate unit
relu_q88.v	      ReLU activation
maxpool_q88.v	      2×2 max-pooling
bram_weight_ctrl.v	 Weight memory/control logic

Project Status

Currently: RTL simulation and functional verification

FPGA synthesis, implementation, and hardware validation are ongoing.

Tools & Technologies:
Verilog
Xilinx Vivado
PYNQ
Python
TensorFlow
Xilinx Zynq-7020 FPGA

Author

Satyarajsinh Gohil
