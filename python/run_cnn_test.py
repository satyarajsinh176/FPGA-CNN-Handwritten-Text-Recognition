from pynq import Overlay
from pynq import MMIO
import time

# ============================================================
# PYNQ-Z2 CNN HARDWARE TEST
# Stage-2 BRAM-friendly RTL
# ============================================================

BITFILE = "cnn_pynq_clean_wrapper.bit"
PIXEL_FILE = "test_image_pixels.hex"

CTRL_BASE = 0x41200000
STAT_BASE = 0x41210000

CTRL_SIZE = 0x1000
STAT_SIZE = 0x1000


# ============================================================
# LOAD OVERLAY
# ============================================================

print("=" * 70)
print("PYNQ-Z2 CNN HARDWARE TEST")
print("=" * 70)

print("Loading:", BITFILE)

ol = Overlay(BITFILE)

ctrl = MMIO(CTRL_BASE, CTRL_SIZE)
stat = MMIO(STAT_BASE, STAT_SIZE)

print("Overlay loaded successfully.")
print()


# ============================================================
# RESET ACCELERATOR
# ============================================================

print("Resetting accelerator...")

ctrl.write(0x0, 0)
time.sleep(0.01)

ctrl.write(0x0, 0b001)

time.sleep(0.001)

print("Reset complete.")
print()


# ============================================================
# LOAD INPUT IMAGE
# ============================================================

print("Loading input image:", PIXEL_FILE)

pixels = []

with open(PIXEL_FILE, "r") as f:

    for line_number, line in enumerate(f, start=1):

        line = line.strip()

        if not line:
            continue

        try:
            value = int(line, 16)
        except ValueError:
            raise ValueError(
                "Invalid hexadecimal value on line {}: {!r}".format(
                    line_number,
                    line
                )
            )

        if value < 0 or value > 0xFFFF:
            raise ValueError(
                "Pixel value out of 16-bit range on line {}: 0x{:X}".format(
                    line_number,
                    value
                )
            )

        pixels.append(value)


print("Loaded", len(pixels), "pixels.")


if len(pixels) != 1024:
    raise RuntimeError(
        "Expected exactly 1024 pixels, but found {}.".format(
            len(pixels)
        )
    )


# ============================================================
# SOFTWARE CHECKSUM
# ============================================================

software_checksum = 0

for px in pixels:

    software_checksum = (
        software_checksum + (px & 0xFFFF)
    ) & 0xFFF


print(
    "Software checksum = 0x{:03X}".format(
        software_checksum
    )
)

print()


# ============================================================
# START IMAGE LOAD
# ============================================================

print("Starting image load...")

ctrl.write(0x0, 0b011)
ctrl.write(0x0, 0b001)


# ============================================================
# SEND 1024 PIXELS
# ============================================================

print("Sending 1024 pixels...")

for index, px in enumerate(pixels):

    # Write pixel data
    ctrl.write(0x8, px)

    # Pixel write pulse
    ctrl.write(0x0, 0b101)

    # Return to normal control state
    ctrl.write(0x0, 0b001)

    if ((index + 1) % 128) == 0:

        print(
            "  Sent {}/1024 pixels".format(
                index + 1
            )
        )


print("All pixels sent.")
print()


# ============================================================
# WAIT FOR CNN RESULT
# ============================================================

print("Waiting for CNN prediction...")

TIMEOUT_SECONDS = 30.0

start_time = time.time()

while True:

    status = stat.read(0x0)

    result_valid = status & 0x1

    if result_valid:
        break

    if (time.time() - start_time) >= TIMEOUT_SECONDS:

        print()
        print(
            "ERROR: CNN timed out after {:.1f} seconds.".format(
                TIMEOUT_SECONDS
            )
        )

        status = stat.read(0x0)

        print(
            "Last status   = 0x{:08X}".format(
                status
            )
        )

        print(
            "debug_status  = {}".format(
                (status >> 12) & 0x3F
            )
        )

        print(
            "checksum      = 0x{:03X}".format(
                status & 0xFFF
            )
        )

        raise RuntimeError(
            "CNN hardware timeout."
        )

    time.sleep(0.001)


# ============================================================
# READ FINAL RESULT
# ============================================================

status = stat.read(0x0)

result_valid = status & 0x1

pred = (status >> 18) & 0x3F

debug_status = (status >> 12) & 0x3F

hardware_checksum = status & 0xFFF


# ============================================================
# PRINT RESULT
# ============================================================

print()

print("=" * 70)
print("CNN RESULT")
print("=" * 70)

print(
    "STATUS          = 0x{:08X}".format(
        status
    )
)

print(
    "RESULT VALID    = {}".format(
        result_valid
    )
)

print(
    "PREDICTION      = {}".format(
        pred
    )
)

print(
    "DEBUG STATUS    = {}".format(
        debug_status
    )
)

print(
    "HW CHECKSUM     = 0x{:03X}".format(
        hardware_checksum
    )
)

print(
    "SW CHECKSUM     = 0x{:03X}".format(
        software_checksum
    )
)


# ============================================================
# CHECKSUM VERIFICATION
# ============================================================

if hardware_checksum == software_checksum:

    print("CHECKSUM        = PASS")

else:

    print("CHECKSUM        = FAIL")


print("=" * 70)


# ============================================================
# FINAL INTERPRETATION
# ============================================================

if hardware_checksum != software_checksum:

    print()
    print("WARNING: Input checksum mismatch.")
    print("The hardware did not receive the expected pixel stream.")

    raise RuntimeError(
        "Input checksum mismatch."
    )


print()
print("Hardware CNN completed successfully.")
print("Prediction =", pred)