# Building emacs-os Without Installing Nix on macOS

If you don't want to install Nix directly on macOS (or NixOS), you can build
and run the emacs-os VM using Lima + QEMU on the host.

## Overview

Two options emerged from this investigation:

- **Option A (current & working):** Lima VM with Nix for builds, QEMU on macOS
  host for VM testing
- **Option B (ideal but needs finishing):** Build a self-contained qcow2 disk
  image inside the Lima VM, then boot it standalone on macOS

## Option A: Lima Build + Host QEMU

### Setup

Create a dedicated Lima VM for emacs-os development:

```bash
limactl start --name=emacs-os .claude/lima-emacs-os.yaml
```

This provisions Ubuntu 24.04 aarch64 with Nix installed, 60GB disk, 8GB RAM.

### Build inside Lima

```bash
limactl shell emacs-os
cd /Users/george/git/oops-all-emacs
git add -N system/disk.nix  # Nix needs files git-tracked
nix build .#vm              # Build the system closure
```

The `result/` symlink contains `kernel`, `initrd`, `init`, `kernel-params`.

### Run on macOS

Requires QEMU on the host (via Homebrew):

```bash
brew install qemu
./scripts/run-vm.sh ./result
```

QEMU uses `hvf` accelerator (Apple Hypervisor.framework) for near-native
performance. The VM mounts `/nix/store` from the host via 9p/virtfs — but
this requires the Nix store to exist on the host.

## Option B: Self-Contained Disk Image (Work in Progress)

The goal is to eliminate the need for host-side `/nix/store` by baking the
store into a qcow2 disk image.

### How it works

- `system/disk.nix` — overrides `vm.nix` to mount `/nix/store` from
  `/dev/vda` (ext4 block device) instead of 9p
- `flake.nix` provides `.#disk-image` (nix store as qcow2) and
  `.#disk-closure` (kernel/initrd with ext4 + virtio_blk modules)
- `make-disk-image.nix` with `onlyNixStore = true` uses LKL (Linux Kernel
  Library) to build the image in userspace — no VM needed, so no KVM
  required inside the Lima build VM
- Kernel + initrd boot the system, Stage 1 mounts the disk, runs the real
  init from the store

### Build

```bash
limactl shell emacs-os
cd /Users/george/git/oops-all-emacs
nix build .#disk-closure       # kernel + initrd + init
nix build .#disk-image         # nix store as qcow2
cp result/nixos.qcow2 emacs-os-disk.qcow2
# Copy closure with resolved symlinks
mkdir -p disk-closure
cp -rL result/. disk-closure/
```

### Run

```bash
./scripts/run-disk-vm.sh ./disk-closure ./emacs-os-disk.qcow2
```

### Known issues

- The `disk.nix` config initially specified `/dev/vdb` but a single virtio
  disk appears as `/dev/vda` — fixed in the current version
- QEMU on macOS needs `-accel hvf` for hardware acceleration, added in
  `run-disk-vm.sh`
- Disk space: the 60GB Lima root disk fills quickly with nix store +
  qcow2 artifacts (~5.9GB each). Run `nix-store --gc` between builds.
- Boot was tested and showed the kernel reaching Stage 1 (systemd initrd),
  discovering `/dev/vda`, and attempting to mount it — with the `/dev/vda`
  fix the mount should succeed

## Comparison: Lima vs Colima

| Aspect | Colima | Lima |
|--------|--------|------|
| Disk size | 20GB root (too small) | Configurable (60GB works) |
| Nix install | Manual | Via provision script |
| QEMU inside | No KVM | No KVM either (VZ backend) |
| Performance | Same (VZ) | Same (VZ) |
| Use case | Docker runtime | General dev VM |

Colima's 20GB root disk is too small for NixOS builds. The nix store alone
takes ~13GB, and the disk image builder needs ~6-8GB of temp space. Lima
with a 60GB disk has room to spare.

## Future Improvement: Install Nix on macOS

The simplest long-term approach is to install the Nix package manager
(single-user, not NixOS) on macOS:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Then everything runs natively:
- `nix build .#vm` cross-compiles for aarch64-linux (Nix handles this)
- `./scripts/run-vm.sh ./result` uses host QEMU with hvf
- No Lima/Colima needed for builds
- No 9p or disk image trickery needed
