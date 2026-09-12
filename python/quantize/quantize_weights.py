"""
quantize_weights.py
---------------------------------------------------
Loads export_model.h5

Converts all weights/biases to Q8.8 INT16

Exports:
    conv1_kernel.hex
    conv1_bias.hex
    ...
    output_bias.hex

Saves into:
    C:\fpga_cnn_accel\weights\fixed\
---------------------------------------------------
"""

import os
import sys
import numpy as np
import tensorflow as tf

# --------------------------------------------------
# Paths
# --------------------------------------------------

EXPORT_MODEL_PATH = (
    r"C:\fpga_cnn_accel\weights\float\export_model.h5"
)

OUTPUT_DIR = (
    r"C:\fpga_cnn_accel\weights\fixed"
)

os.makedirs(OUTPUT_DIR, exist_ok=True)

Q = 256

INT16_MIN = -32768
INT16_MAX = 32767

# --------------------------------------------------
# Quantization
# --------------------------------------------------

def float_to_q88(x):

    q = np.round(x * Q)

    q = np.clip(
        q,
        INT16_MIN,
        INT16_MAX
    )

    return q.astype(np.int16)

# --------------------------------------------------
# Hex writer
# --------------------------------------------------

def write_hex(filename, data):

    flat = data.flatten()

    with open(filename, "w") as f:

        for value in flat:

            value = np.uint16(value)

            f.write(
                f"{value:04X}\n"
            )

# --------------------------------------------------
# Main
# --------------------------------------------------

def main():

    print("="*60)
    print("Q8.8 QUANTIZATION")
    print("="*60)

    model = tf.keras.models.load_model(
        EXPORT_MODEL_PATH
    )

    total_weights = 0

    for layer in model.layers:

        weights = layer.get_weights()

        if len(weights) == 0:
            continue

        print(f"\nLayer: {layer.name}")

        for idx, tensor in enumerate(weights):

            if idx == 0:
                tensor_name = "kernel"
            else:
                tensor_name = "bias"

            q_tensor = float_to_q88(
                tensor
            )

            total_weights += q_tensor.size

            print(
                f"  {tensor_name:<8s}"
                f" shape={str(q_tensor.shape):20s}"
                f" min={q_tensor.min():6d}"
                f" max={q_tensor.max():6d}"
            )

            filename = os.path.join(
                OUTPUT_DIR,
                f"{layer.name}_{tensor_name}.hex"
            )

            write_hex(
                filename,
                q_tensor
            )

    print("\n" + "="*60)
    print(f"Total values exported : {total_weights:,}")
    print(
        f"INT16 storage         : "
        f"{total_weights*2/1024:.1f} KB"
    )
    print("="*60)

    print("\nDONE")

if __name__ == "__main__":
    main()