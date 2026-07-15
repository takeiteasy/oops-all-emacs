#!/usr/bin/env bash
# Boot emacs-os VM using a disk image for the Nix store.
# Requires: qemu-system-aarch64 (macOS native, uses hvf acceleration)
#
# Usage:
#   nix build .#disk-closure && nix build .#disk-image && \
#     cp result/nixos.qcow2 emacs-os-disk.qcow2 && \
#     ./scripts/run-disk-vm.sh
#
# Or after a Lima/Colima build:
#   ./scripts/run-disk-vm.sh ./disk-closure ./emacs-os-disk.qcow2
#
# Environment:
#   EMACS_OS_HEADLESS=1   → serial console only
#   EMACS_OS_MEM=4096     → VM memory in MB
set -euo pipefail

CLOSURE="${1:-}"
DISK="${2:-emacs-os-disk.qcow2}"
MEM="${EMACS_OS_MEM:-4096}"

# If no closure path given, try result symlink, then default
if [ -z "$CLOSURE" ]; then
  if [ -L result.closure ]; then
    CLOSURE="$(readlink -f result.closure)"
  elif [ -d result ] && [ -f result/kernel-params ]; then
    CLOSURE="$(readlink -f result)"
  else
    echo "Error: no closure path given and no result/ directory found." >&2
    echo "Usage: $0 <closure-path> [disk-image]" >&2
    exit 1
  fi
fi

# Resolve symlinks
CLOSURE="$(readlink -f "$CLOSURE")"
DISK="$(readlink -f "$DISK")"

# Validate inputs
for f in kernel initrd kernel-params; do
  if [ ! -e "$CLOSURE/$f" ]; then
    echo "Error: $CLOSURE/$f not found" >&2
    exit 1
  fi
done
if [ ! -f "$DISK" ]; then
  echo "Error: disk image $DISK not found" >&2
  exit 1
fi

# Find QEMU
if [ -n "${QEMU:-}" ]; then
  : # user-provided
elif command -v qemu-system-aarch64 &>/dev/null; then
  QEMU=qemu-system-aarch64
elif [ -x /opt/homebrew/bin/qemu-system-aarch64 ]; then
  QEMU=/opt/homebrew/bin/qemu-system-aarch64
else
  echo "Error: qemu-system-aarch64 not found" >&2
  exit 1
fi

KERNEL_PARAMS="$(cat "$CLOSURE/kernel-params") init=$CLOSURE/init"

DISPLAY_ARGS=()
if [ "${EMACS_OS_HEADLESS:-}" = "1" ]; then
  DISPLAY_ARGS+=(-nographic)
else
  DISPLAY_ARGS+=(
    -device virtio-gpu-pci
    -display cocoa
    -serial stdio
    -device virtio-keyboard-pci
    -device virtio-tablet-pci
  )
fi

echo "Booting emacs-os VM (disk image)..."
echo "  Closure: $CLOSURE"
echo "  Disk:    $DISK"
echo "  Memory:  ${MEM}M"
echo "  Display: ${EMACS_OS_HEADLESS:+headless}${EMACS_OS_HEADLESS:-graphical}"
echo ""
echo "Press Ctrl-A X to exit QEMU."
echo ""

exec "$QEMU" \
  -machine virt,gic-version=2 \
  -accel hvf \
  -cpu max \
  -m "$MEM" \
  -kernel "$CLOSURE/kernel" \
  -initrd "$CLOSURE/initrd" \
  -append "$KERNEL_PARAMS" \
  -drive "file=$DISK,if=virtio,format=qcow2" \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-device,netdev=net0 \
  "${DISPLAY_ARGS[@]}"
