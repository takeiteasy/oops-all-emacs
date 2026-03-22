# emacs-os

A Linux OS where GNU Emacs is PID 1, the init system, the window manager, and
the entire user environment. Inspired by Lisp Machines (Symbolics, LMI): a
single live-programmable environment on top of a Linux kernel.

## Architecture

Two phases. Phase 1 uses X11/EXWM. Phase 2 replaces X11 with a native OpenGL
compositor written in Elisp.

### Phase 1 (current)

Two distinct Emacs binaries:

- **emacs-pid1** — statically linked, no X11, PID1-patched Emacs 30.2. Runs as
  `init=` on the kernel cmdline. Supervises services via el-init.
- **emacs-graphical** — dynamic, X11/GTK3. Runs EXWM as the desktop session.
  (Not yet built — Milestone 1.5.)

```
Linux kernel
    └── emacs-pid1 --pid1  (PID 1, el-init supervisor)
            ├── D-Bus
            ├── PipeWire
            ├── NetworkManager
            ├── Xorg
            └── emacs-graphical  (EXWM desktop session)
```

### Phase 2 (future)

Replaces Xorg with emacs-gl → EGL/GBM → DRM/KMS. No display server. Direct GPU
access from Elisp. Elisp Wayland compositor for legacy app compat via XWayland.

## Repo Structure

```
flake.nix                  # Entry point. Inputs: nixpkgs (nixos-unstable), el-init
flake.lock                 # Pinned input versions

pkgs/
  emacs-pid1/default.nix   # Static PID1 Emacs 30.2 (6 static lib sub-derivations)
  elinit/default.nix       # el-init Elisp package (installed to share/emacs/site-lisp)
  elinit-libexec/default.nix  # el-init C helpers: elinit-logd, runas, rlimits

system/
  vm.nix                   # NixOS QEMU VM config (Milestone 1.2 test environment)
  elinit-init.nix          # NixOS module: el-init as PID 1 (replaces systemd)

scripts/
  run-vm.sh                # Launch QEMU VM on macOS (uses system.build.toplevel)

emacs-os-plan.md           # Full milestone-by-milestone project plan
```

## Build

Target system is **aarch64-linux** (built via nix-darwin linux-builder on Apple
Silicon). All packages live under `packages.aarch64-linux.*`.

```bash
# Build the PID1 Emacs binary (~10 min first time, cached after)
nix build .#packages.aarch64-linux.emacs-pid1

# Build the NixOS system closure + launch VM with macOS QEMU
nix build .#vm && ./scripts/run-vm.sh ./result

# Build individual packages
nix build .#packages.aarch64-linux.elinit
nix build .#packages.aarch64-linux.elinit-libexec
```

### Prerequisites

- Nix with flakes enabled (`experimental-features = nix-command flakes`)
- nix-darwin with `nix.linux-builder.enable = true` (provides the aarch64-linux builder)

## Key Design Decisions

**emacs-pid1 is fully static.** nixpkgs' Emacs is dynamically linked — using
`overrideAttrs` would not produce a static binary. All 6 C dependencies (ncurses,
GMP, nettle, GnuTLS, libxml2, tree-sitter) are compiled from source as static
archives inside the derivation. The build runs the full el-init verification
suite (static linkage, PID1 patch checks, feature checks) as part of `installPhase`.

**el-init is a flake input, not a submodule.** Pinned in `flake.lock`, patches
referenced directly as `${el-init}/static-builds/patches/`. Update with
`nix flake update el-init`.

**PID1 patches do not auto-activate.** The `--pid1` flag must be passed
explicitly. Without it, the binary behaves as a normal Emacs. el-init Elisp is
not loaded implicitly — it must be required in `init.el`.

**GLArea patches are Phase 2 only.** emacs-gl targets Emacs 27; the patches do
not apply to Emacs 30.2. Phase 1 (EXWM) has no dependency on OpenGL.

## Current Status

| Milestone | Description | Status |
|-----------|-------------|--------|
| 1.1 | Patched Emacs derivation (static, PID1 patches) | ✅ Done |
| 1.2 | Bootable QEMU VM | ✅ Done |
| 1.3 | el-init as PID 1 (`init=` kernel param) | ✅ Done |
| 1.4 | Core services (D-Bus, PipeWire, NetworkManager, Xorg) | Pending |
| 1.5 | EXWM graphical desktop session | Pending |

## Key Dependencies

| Component | Source | Role |
|-----------|--------|------|
| el-init | github.com/emacs-os/el-init | PID 1 patches + service supervisor |
| EXWM | elpa/exwm | X11 window manager (Phase 1) |
| emacs-gl | github.com/Jimx-/emacs-gl | OpenGL Elisp bindings (Phase 2) |
| nixpkgs | nixos-unstable | System packages and NixOS VM infrastructure |
