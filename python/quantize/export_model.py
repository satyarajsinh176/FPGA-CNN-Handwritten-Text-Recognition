"""
export_model.py
-------------------------------------------------------
Loads trained model.h5
Builds FPGA export model
Folds BatchNorm into Conv layers
Copies Dense weights
Saves export_model.h5

Output:
    C:\fpga_cnn_accel\weights\float\export_model.h5
-------------------------------------------------------
"""

import sys
import os

# -------------------------------------------------------
# Add training folder to import path
# -------------------------------------------------------

sys.path.append(
    r"C:\fpga_cnn_accel\python\train"
)

from model import (
    build_model,
    build_export_model,
    copy_weights_to_export
)

# -------------------------------------------------------
# Paths
# -------------------------------------------------------

FLOAT_MODEL_PATH = (
    r"C:\fpga_cnn_accel\weights\float\model.h5"
)

EXPORT_MODEL_PATH = (
    r"C:\fpga_cnn_accel\weights\float\export_model.h5"
)

# -------------------------------------------------------
# Main
# -------------------------------------------------------

def main():

    print("=" * 60)
    print("FPGA CNN EXPORT MODEL GENERATOR")
    print("=" * 60)

    # ---------------------------------------------------
    # Load training architecture
    # ---------------------------------------------------

    print("\nLoading training model...")

    train_model = build_model()

    train_model.load_weights(
        FLOAT_MODEL_PATH
    )

    print("Training weights loaded.")

    # ---------------------------------------------------
    # Build FPGA export architecture
    # ---------------------------------------------------

    print("\nBuilding export model...")

    export_model = build_export_model()

    # ---------------------------------------------------
    # Fold BatchNorm
    # ---------------------------------------------------

    print("\nFolding BatchNorm layers...")

    export_model = copy_weights_to_export(
        train_model,
        export_model
    )

    # ---------------------------------------------------
    # Save export model
    # ---------------------------------------------------

    print("\nSaving export model...")

    export_model.save(
        EXPORT_MODEL_PATH
    )

    print("\nSUCCESS")
    print(f"Saved:\n{EXPORT_MODEL_PATH}")

    print("\nExport model summary:")
    export_model.summary()

    print("\nDone.")


if __name__ == "__main__":
    main()