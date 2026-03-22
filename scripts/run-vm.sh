#!/usr/bin/env bash
# Boot the emacs-os NixOS system in QEMU on macOS (Apple Silicon).
#
# Usage:
#   nix build .#packages.aarch64-linux.vm && ./scripts/run-vm.sh ./result
#   ./scripts/run-vm.sh /nix/store/...-nixos-system-emacs-os-...
#
# Environment variables:
#   EMACS_OS_DISK     — path to persistent qcow2 disk (default: /tmp/emacs-os.qcow2)
#   EMACS_OS_HEADLESS — set to 1 for headless mode (serial console only)
#   EMACS_OS_MEM      — VM memory in MB (default: 4096)
#   QEMU              — path to qemu-system-aarch64 (auto-detected)
set -euo pipefail

SYSTEM="${1:?Usage: $0 <path-to-nixos-system>}"
shift
DISK="${EMACS_OS_DISK:-/tmp/emacs-os.qcow2}"
MEM="${EMACS_OS_MEM:-4096}"

# Resolve symlinks (nix build produces a ./result symlink)
SYSTEM="$(readlink -f "$SYSTEM")"

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

# Verify system closure
for f in kernel initrd init kernel-params; do
  if [ ! -e "$SYSTEM/$f" ]; then
    echo "Error: $SYSTEM/$f not found — is this a NixOS system closure?" >&2
    exit 1
  fi
done

# Create disk image if needed
if [ ! -f "$DISK" ]; then
  echo "Creating VM disk at $DISK ..."
  "$QEMU" --version | head -1
  qemu-img create -f qcow2 "$DISK" 4G
fi

KERNEL_PARAMS="$(cat "$SYSTEM/kernel-params") init=$SYSTEM/init"

# Display mode: graphical (default) or headless
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

echo "Booting emacs-os VM..."
echo "  System:  $SYSTEM"
echo "  Disk:    $DISK"
echo "  Memory:  ${MEM}M"
echo "  Display: ${EMACS_OS_HEADLESS:+headless}${EMACS_OS_HEADLESS:-graphical}"
echo "  Kernel:  $(readlink -f "$SYSTEM/kernel")"
echo ""
echo "Press Ctrl-A X to exit QEMU."
echo ""

exec "$QEMU" \
  -machine virt,gic-version=2 \
  -cpu max \
  -m "$MEM" \
  -kernel "$SYSTEM/kernel" \
  -initrd "$SYSTEM/initrd" \
  -append "$KERNEL_PARAMS" \
  -drive "file=$DISK,if=virtio,format=qcow2" \
  -virtfs "local,path=/nix/store,mount_tag=nix-store,security_model=none,readonly=on" \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-device,netdev=net0 \
  "${DISPLAY_ARGS[@]}" \
  "$@"
