"""
train.py  —  FINAL VERSION
--------------------------
What changed and why:

1. NO augmentation
   EMNIST images are already centered and size-normalized.
   Adding rotation/shift was making training harder without helping
   generalization — val accuracy was lower WITH augmentation than without.

2. Wider model (in model.py): 16/32/64 filters, Dense 256
   Old model: 4×4×32 = 512 features for 62 classes = 8 features/class (too tight)
   New model: 4×4×64 = 1024 features for 62 classes = 16 features/class

3. ReduceLROnPlateau patience=4 (was 3 or 5)
   Balanced — not too aggressive, not too slow.

4. EarlyStopping patience=12
   Val accuracy with BatchNorm is smoother — 12 is sufficient.

5. Epochs=40
   Wider model + no augmentation converges faster.

Target: 85–90% val accuracy

Save to: C:\\fpga_cnn_accel\\python\\train\\train.py
"""

import sys
import os
import numpy as np
import matplotlib.pyplot as plt
import tensorflow as tf
from tensorflow.keras import optimizers, callbacks

sys.path.insert(0, os.path.dirname(__file__))
from data_loader import load_emnist
from model import build_model

# ─── Config ────────────────────────────────────────────────────────────────────
EPOCHS        = 40
NUM_CLASSES   = 62
LEARNING_RATE = 0.001
MODEL_SAVE    = r'C:\fpga_cnn_accel\weights\float\model.h5'
CURVES_SAVE   = r'C:\fpga_cnn_accel\weights\float\training_curves.png'

# ─── Class weights ─────────────────────────────────────────────────────────────
def compute_class_weights(ds_train, num_classes=62, scan_batches=100):
    print("Computing class weights...")
    counts = np.zeros(num_classes, dtype=np.float64)
    for _, labels in ds_train.take(scan_batches):
        for l in labels.numpy():
            counts[l] += 1
    counts  = np.where(counts == 0, 1, counts)
    total   = counts.sum()
    w       = total / (num_classes * counts)
    w       = w / w.mean()
    print(f"  Weight range: [{w.min():.2f}, {w.max():.2f}]")
    return {i: w[i] for i in range(num_classes)}

# ─── Plot curves ───────────────────────────────────────────────────────────────
def plot_curves(history, save_path):
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 4))

    acc     = history.history['accuracy']
    val_acc = history.history['val_accuracy']
    loss    = history.history['loss']
    val_los = history.history['val_loss']
    best_ep = int(np.argmax(val_acc))

    ax1.plot(acc,     label='Train')
    ax1.plot(val_acc, label='Val')
    ax1.axvline(x=best_ep, color='red', linestyle='--', alpha=0.5)
    ax1.annotate(f'Best: {val_acc[best_ep]:.3f}',
                 xy=(best_ep, val_acc[best_ep]),
                 xytext=(best_ep+0.5, val_acc[best_ep]-0.02),
                 color='red', fontsize=8)
    ax1.set_title('Accuracy'); ax1.set_xlabel('Epoch')
    ax1.set_ylabel('Accuracy'); ax1.legend(); ax1.grid(True)

    ax2.plot(loss,    label='Train')
    ax2.plot(val_los, label='Val')
    ax2.set_title('Loss'); ax2.set_xlabel('Epoch')
    ax2.set_ylabel('Loss'); ax2.legend(); ax2.grid(True)

    plt.suptitle('FPGA CNN — Training Curves (Final)', fontsize=13)
    plt.tight_layout()
    plt.savefig(save_path, dpi=120)
    plt.close()
    print(f"Training curves saved → {save_path}")

# ─── Main ──────────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    print("=" * 60)
    print("  FPGA CNN — Final Training")
    print("  Model   : Conv 16/32/64 + Dense 256 + BN + Dropout 0.3")
    print("  Augment : NONE (EMNIST is pre-normalized)")
    print("  LR      : 0.001, reduce on plateau (patience=4)")
    print("  Stop    : patience=12 on val_accuracy")
    print("=" * 60)

    # 1. Load data (no augmentation)
    ds_train, ds_val, ds_test, _ = load_emnist()

    # 2. Build and compile
    model = build_model(input_shape=(32, 32, 1), num_classes=NUM_CLASSES)
    model.compile(
        optimizer=optimizers.Adam(learning_rate=LEARNING_RATE),
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )
    print(f"\nModel parameters: {model.count_params():,}\n")

    # 3. Class weights
    class_weights = compute_class_weights(ds_train)

    # 4. Callbacks
    os.makedirs(os.path.dirname(MODEL_SAVE), exist_ok=True)

    cb_ckpt = callbacks.ModelCheckpoint(
        filepath=MODEL_SAVE,
        monitor='val_accuracy',
        save_best_only=True,
        verbose=1
    )
    cb_lr = callbacks.ReduceLROnPlateau(
        monitor='val_loss',
        factor=0.5,
        patience=4,
        min_lr=1e-6,
        verbose=1
    )
    cb_stop = callbacks.EarlyStopping(
        monitor='val_accuracy',
        patience=12,
        restore_best_weights=True,
        verbose=1
    )

    # 5. Train
    print(f"Starting training — up to {EPOCHS} epochs\n")
    history = model.fit(
        ds_train,
        validation_data=ds_val,
        epochs=EPOCHS,
        class_weight=class_weights,
        callbacks=[cb_ckpt, cb_lr, cb_stop],
        verbose=1
    )

    # 6. Evaluate
    print("\nEvaluating on test set...")
    test_loss, test_acc = model.evaluate(ds_test, verbose=0)
    best_val = max(history.history['val_accuracy'])
    best_ep  = int(np.argmax(history.history['val_accuracy'])) + 1

    print(f"\n{'='*60}")
    print(f"  Best val accuracy : {best_val*100:.2f}%  (epoch {best_ep})")
    print(f"  Test  accuracy    : {test_acc*100:.2f}%")
    print(f"  Test  loss        : {test_loss:.4f}")
    print(f"{'='*60}")

    if best_val >= 0.90:
        print("  ✅ Target met — val accuracy ≥ 90%")
    elif best_val >= 0.85:
        print("  ✅ Acceptable — 85%+ is solid for FPGA quantization")
    else:
        print(f"  ⚠️  {(0.90-best_val)*100:.1f}% below 90% target")

    # 7. Plot
    plot_curves(history, CURVES_SAVE)
    print(f"\nModel saved → {MODEL_SAVE}")
    print("✅ Training complete — ready for quantization (Phase 3)")