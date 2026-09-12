"""
data_loader.py
--------------
Loads EMNIST ByClass dataset, resizes 28x28 → 32x32,
normalizes, splits into train/val/test sets, prints stats,
and saves a sample grid image.

Save to: C:\fpga_cnn_accel\python\train\data_loader.py
"""

import numpy as np
import matplotlib.pyplot as plt
import tensorflow as tf
import tensorflow_datasets as tfds

# ─── Config ────────────────────────────────────────────────────────────────────
TARGET_SIZE   = 32          # FPGA input: 32×32
NUM_CLASSES   = 62          # EMNIST ByClass: A-Z, a-z, 0-9
VAL_SPLIT     = 0.1         # 10% of training set → validation
BATCH_SIZE    = 128
AUTOTUNE      = tf.data.AUTOTUNE

# ─── EMNIST label map ───────────────────────────────────────────────────────────
# ByClass labels: 0-9 → digits, 10-35 → A-Z, 36-61 → a-z
def label_to_char(label):
    if label < 10:
        return chr(ord('0') + label)
    elif label < 36:
        return chr(ord('A') + label - 10)
    else:
        return chr(ord('a') + label - 36)

# ─── Preprocessing ─────────────────────────────────────────────────────────────
def preprocess(sample):
    """
    - Cast to float32, normalize [0, 255] → [0.0, 1.0]
    - Resize 28×28 → 32×32
    - EMNIST images are stored transposed — fix orientation
    """
    image = tf.cast(sample['image'], tf.float32) / 255.0   # normalize
    image = tf.transpose(image, perm=[1, 0, 2])            # fix EMNIST transpose
    image = tf.image.resize(image, [TARGET_SIZE, TARGET_SIZE])  # 28→32
    label = sample['label']
    return image, label

# ─── Load dataset ──────────────────────────────────────────────────────────────
def load_emnist():
    print("Loading EMNIST ByClass (first run will download ~500 MB)...")

    # Load full train and test splits
    ds_train_full, info = tfds.load(
        'emnist/byclass',
        split='train',
        with_info=True,
        shuffle_files=True
    )
    ds_test = tfds.load('emnist/byclass', split='test')

    total_train = info.splits['train'].num_examples
    total_test  = info.splits['test'].num_examples
    print(f"  Raw train samples : {total_train:,}")
    print(f"  Raw test  samples : {total_test:,}")

    # Shuffle before splitting so val isn't from a single class
    ds_train_full = ds_train_full.shuffle(buffer_size=10000, seed=42)

    # Carve out validation set (10% of train)
    val_size = int(total_train * VAL_SPLIT)
    ds_val   = ds_train_full.take(val_size)
    ds_train = ds_train_full.skip(val_size)

    print(f"  Train  : {total_train - val_size:,}")
    print(f"  Val    : {val_size:,}")
    print(f"  Test   : {total_test:,}")

    # Apply preprocessing
    ds_train = (ds_train
                .map(preprocess, num_parallel_calls=AUTOTUNE)
                .batch(BATCH_SIZE)
                .prefetch(AUTOTUNE))

    ds_val   = (ds_val
                .map(preprocess, num_parallel_calls=AUTOTUNE)
                .batch(BATCH_SIZE)
                .prefetch(AUTOTUNE))

    ds_test  = (ds_test
                .map(preprocess, num_parallel_calls=AUTOTUNE)
                .batch(BATCH_SIZE)
                .prefetch(AUTOTUNE))

    return ds_train, ds_val, ds_test, info

# ─── Class distribution check ──────────────────────────────────────────────────
def print_class_stats(ds, name, num_batches=20):
    """Count label occurrences across a few batches and print distribution."""
    counts = np.zeros(NUM_CLASSES, dtype=np.int64)
    for images, labels in ds.take(num_batches):
        for l in labels.numpy():
            counts[l] += 1
    total = counts.sum()
    print(f"\n{name} class distribution (first {num_batches} batches, {total} samples):")
    for cls in range(NUM_CLASSES):
        bar = '█' * int(counts[cls] / total * 50)
        print(f"  {label_to_char(cls)} (cls {cls:2d}): {counts[cls]:5d}  {bar}")

# ─── Sample grid ───────────────────────────────────────────────────────────────
def save_sample_grid(ds, filename='sample_grid.png', grid=(8, 8)):
    """Save a grid of sample images with their labels."""
    rows, cols = grid
    n = rows * cols

    images_list, labels_list = [], []
    for images, labels in ds.take(1):                     # one batch
        images_list = images.numpy()[:n]
        labels_list = labels.numpy()[:n]

    fig, axes = plt.subplots(rows, cols, figsize=(cols * 1.2, rows * 1.4))
    fig.suptitle('EMNIST ByClass — sample images (32×32)', fontsize=12)

    for i, ax in enumerate(axes.flat):
        if i < len(images_list):
            ax.imshow(images_list[i].squeeze(), cmap='gray', vmin=0, vmax=1)
            ax.set_title(label_to_char(labels_list[i]), fontsize=9)
        ax.axis('off')

    plt.tight_layout()
    plt.savefig(filename, dpi=120)
    plt.close()
    print(f"\nSample grid saved → {filename}")

# ─── Verify a single batch ─────────────────────────────────────────────────────
def verify_batch(ds, name):
    for images, labels in ds.take(1):
        print(f"\n{name} batch:")
        print(f"  images shape : {images.shape}  dtype: {images.dtype}")
        print(f"  labels shape : {labels.shape}  dtype: {labels.dtype}")
        print(f"  pixel range  : [{images.numpy().min():.3f}, {images.numpy().max():.3f}]")
        unique = np.unique(labels.numpy())
        print(f"  classes seen : {len(unique)}  (sample: {[label_to_char(l) for l in unique[:10]]})")

# ─── Main ──────────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    ds_train, ds_val, ds_test, info = load_emnist()

    verify_batch(ds_train, 'Train')
    verify_batch(ds_val,   'Val')
    verify_batch(ds_test,  'Test')

    print_class_stats(ds_train, 'Train')

    save_sample_grid(ds_train, filename='sample_grid.png')

    print("\n✅ Data loader complete — datasets ready for model.py")
    print("   Return values: ds_train, ds_val, ds_test")