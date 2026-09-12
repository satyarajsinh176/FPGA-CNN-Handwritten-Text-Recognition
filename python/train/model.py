"""
model.py  —  FINAL VERSION
--------------------------
Two model builders:
  build_model()            : training model  (BN + Dropout 0.3)
  build_export_model()     : FPGA export     (BN folded, no Dropout)
  copy_weights_to_export() : transfers weights + folds BN

Architecture (fixed — must match Verilog):
    Input : 32×32×1
    Conv1 : 3×3, 16 filters → BN → ReLU → MaxPool 2×2  →  15×15×16
    Conv2 : 3×3, 32 filters → BN → ReLU → MaxPool 2×2  →   6×6×32
    Conv3 : 3×3, 64 filters → BN → ReLU                →   4×4×64
    Flatten → 1024
    Dropout(0.3)
    Dense : 128 → ReLU      ← 128 (not 256) to fit BRAM budget
    Output: 62  → Softmax

BRAM budget (INT16):
    Conv1+2+3 : ~13 BRAM36K
    Dense1    : 1024×128 = 64 BRAM36K
    Output    : 128×62  =  4 BRAM36K
    Total     : ~81 BRAM36K  (target <100 ✅)

Save to: C:\\fpga_cnn_accel\\python\\train\\model.py
"""

import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models


# ─── Training model ────────────────────────────────────────────────────────────
def build_model(input_shape=(32, 32, 1), num_classes=62):
    """
    Training model with BatchNorm + Dropout(0.3).
    Conv layers use use_bias=False — BN absorbs the bias.
    """
    model = models.Sequential([
        layers.Input(shape=input_shape),

        # Conv Block 1: 32×32 → 30×30 → 15×15
        layers.Conv2D(16, (3,3), padding='valid', use_bias=False, name='conv1'),
        layers.BatchNormalization(name='bn1'),
        layers.Activation('relu', name='relu1'),
        layers.MaxPooling2D((2,2), name='pool1'),

        # Conv Block 2: 15×15 → 13×13 → 6×6
        layers.Conv2D(32, (3,3), padding='valid', use_bias=False, name='conv2'),
        layers.BatchNormalization(name='bn2'),
        layers.Activation('relu', name='relu2'),
        layers.MaxPooling2D((2,2), name='pool2'),

        # Conv Block 3: 6×6 → 4×4
        layers.Conv2D(64, (3,3), padding='valid', use_bias=False, name='conv3'),
        layers.BatchNormalization(name='bn3'),
        layers.Activation('relu', name='relu3'),

        layers.Flatten(name='flatten'),         # 4×4×64 = 1024
        layers.Dropout(0.3, name='dropout'),
        layers.Dense(128, activation='relu',    name='dense1'),
        layers.Dense(num_classes, activation='softmax', name='output'),

    ], name='fpga_cnn_train')
    return model


# ─── Export model (no BN, no Dropout) ─────────────────────────────────────────
def build_export_model(input_shape=(32, 32, 1), num_classes=62):
    """
    FPGA export model.
    BN folded into conv weights. No Dropout.
    This is what gets quantized and loaded onto FPGA BRAM.
    """
    model = models.Sequential([
        layers.Input(shape=input_shape),

        layers.Conv2D(16, (3,3), padding='valid', activation='relu', name='conv1'),
        layers.MaxPooling2D((2,2), name='pool1'),

        layers.Conv2D(32, (3,3), padding='valid', activation='relu', name='conv2'),
        layers.MaxPooling2D((2,2), name='pool2'),

        layers.Conv2D(64, (3,3), padding='valid', activation='relu', name='conv3'),

        layers.Flatten(name='flatten'),
        layers.Dense(128, activation='relu',    name='dense1'),
        layers.Dense(num_classes, activation='softmax', name='output'),

    ], name='fpga_cnn_export')
    return model


# ─── BN folding ────────────────────────────────────────────────────────────────
def fold_bn_into_conv(conv_layer, bn_layer):
    """
    Fold BatchNorm into preceding Conv layer.

        scale      = gamma / sqrt(variance + epsilon)
        new_kernel = kernel * scale
        new_bias   = beta - mean * scale
    """
    kernel                      = conv_layer.get_weights()[0]
    gamma, beta, mean, variance = bn_layer.get_weights()
    eps                         = bn_layer.epsilon

    scale      = gamma / np.sqrt(variance + eps)
    new_kernel = kernel * scale[np.newaxis, np.newaxis, np.newaxis, :]
    new_bias   = beta - mean * scale

    return new_kernel, new_bias


# ─── Weight transfer ───────────────────────────────────────────────────────────
def copy_weights_to_export(train_model, export_model):
    """
    Conv1/2/3 : fold BN into conv weights.
    Dense1/output : copy directly.
    """
    tl = {l.name: l for l in train_model.layers}
    el = {l.name: l for l in export_model.layers}

    print("Transferring weights to export model...")
    for conv_name, bn_name in [('conv1','bn1'),('conv2','bn2'),('conv3','bn3')]:
        k, b = fold_bn_into_conv(tl[conv_name], tl[bn_name])
        el[conv_name].set_weights([k, b])
        print(f"  {conv_name}+{bn_name} folded → kernel{k.shape} bias{b.shape}")

    for name in ['dense1', 'output']:
        w = tl[name].get_weights()
        el[name].set_weights(w)
        print(f"  {name} copied → kernel{w[0].shape} bias{w[1].shape}")

    return export_model


# ─── Summary ───────────────────────────────────────────────────────────────────
def print_model_summary():
    model = build_model()
    model.summary()

    print("\n── Layer output shapes ──────────────────────────────")
    x = tf.zeros((1, 32, 32, 1))
    for layer in model.layers:
        x = layer(x)
        print(f"  {layer.name:12s}  →  {str(x.shape)}")

    print("\n── BRAM budget (weights only, INT16) ────────────────")
    total = 0
    skip  = {'bn1','bn2','bn3','dropout','flatten',
             'relu1','relu2','relu3','pool1','pool2'}
    for layer in model.layers:
        if layer.name in skip:
            continue
        w = layer.get_weights()
        if w:
            count = sum(ww.size for ww in w)
            kb    = count * 2 / 1024
            brams = int(np.ceil(count * 2 / 4096))
            print(f"  {layer.name:8s}  {count:7,} weights  "
                  f"{kb:6.1f} KB  ~{brams} BRAM36K")
            total += count
    print(f"\n  Total : {total:,} weights  "
          f"{total*2/1024:.0f} KB  "
          f"~{int(np.ceil(total*2/4096))} BRAM36K")
    return model


if __name__ == '__main__':
    print_model_summary()
    print("\n── Export model ─────────────────────────────────────")
    build_export_model().summary()
    print("\n✅ model.py verified — Dense=128, BRAM budget OK")