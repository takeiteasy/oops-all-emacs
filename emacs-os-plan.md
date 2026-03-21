# Emacs-OS Project Plan

## Overview

Emacs-OS is a Linux-based operating system where GNU Emacs serves as PID 1,
the init system, the window manager, and the primary user environment. The
system uses el-init for service supervision, EXWM as the initial window manager,
and Nix for reproducible package management. A second phase replaces the X11
display stack with a native OpenGL compositor written in Emacs Lisp using
emacs-gl, eliminating the dependency on a traditional display server entirely.

The philosophical inspiration is the Lisp Machines of the 1970s and 80s
(Symbolics, LMI), where the entire system — editor, debugger, window system,
OS — was a single live-programmable Lisp environment. Emacs-OS pursues this
vision on modern hardware using the Linux kernel as the only non-Lisp layer.

---

## Key Repositories and Dependencies

| Component | Source | Role |
|---|---|---|
| el-init | github.com/emacs-os/el-init | PID 1, service supervisor |
| emacs-gl | github.com/Jimx-/emacs-gl | OpenGL bindings for Elisp (Phase 2) |
| EXWM | elpa/exwm | X11 window manager (Phase 1) |
| Nix / nixpkgs | nixos.org | Package manager and system build |
| XWayland | freedesktop.org | Legacy X11 app compatibility (Phase 2) |
| vterm | github.com/akermu/emacs-libvterm | Terminal emulation |

---

## Architecture

### Phase 1 (EXWM)

Two distinct Emacs binaries are used:

- **emacs-pid1** — statically linked, no X11/GUI, PID1-patched. Serves as the
  init process only. Built from source with all dependencies as static archives.
- **emacs-graphical** — dynamically linked, X11/GTK3, standard nixpkgs Emacs
  with PID1 patches applied via `overrideAttrs`. Used for the desktop session.

```
Linux kernel
    |
el-init (PID 1 — emacs-pid1: static, nox, --pid1 flag)
    |
el-init managed services:
    ├── D-Bus daemon
    ├── PipeWire (audio)
    ├── NetworkManager
    ├── Xorg
    └── [user services]
    |
emacs-graphical (desktop session — dynamic, X11/GTK3)
    ├── EXWM (X11 window manager)
    ├── vterm (terminal emulation)
    └── Emacs config (the desktop environment)
```

### Phase 2 (Native Compositor)

```
Linux kernel
    |
el-init (PID 1)
    |
el-init managed services:
    ├── D-Bus daemon
    ├── PipeWire
    ├── NetworkManager
    └── XWayland (legacy app compat)
    |
Emacs (graphical session)
    ├── emacs-gl → EGL/GBM → DRM/KMS (direct GPU, no display server)
    ├── evdev input module (raw kernel input)
    ├── Elisp Wayland compositor
    └── Emacs config (the desktop environment)
```

---

## Design Principles

**Display-stack agnosticism.** El-init service definitions must make no
assumptions about the display stack. Both the Xorg service (Phase 1) and the
compositor service (Phase 2) should be members of `graphical.target`. The rest
of the system waits on `graphical.target` without knowing what provided it.
Swapping display stacks should require only disabling one el-init service and
enabling another.

**Nix as the source of truth.** The entire system — including the patched Emacs
binary, all el-init unit files, and all system services — is expressed as Nix
derivations. The system is fully reproducible and rollback-able. No manual
configuration outside of Nix expressions.

**Elisp as the configuration language.** Where configuration is needed above the
Nix level (user services, desktop behaviour, keybindings), it is Emacs Lisp.
No shell scripts, no YAML, no TOML. The system is live-patchable at runtime
in the Lisp Machine tradition.

**Minimal C surface area.** C code is confined to thin shim modules where Emacs
cannot reach kernel interfaces directly (emacs-gl for GPU access, an evdev
module for raw input, el-init's existing helpers for setrlimit and setuid).
All logic lives in Elisp.

---

## Phase 1: EXWM — Bootable and Daily-Driveable

### Milestone 1.1 — Patched Emacs Nix Derivation

The foundation of the entire project. A Nix derivation that:

- Applies el-init's PID 1 static build patches onto a recent Emacs release
- Builds with `--with-modules` and the static linking flags required for
  PID 1 operation
- Produces a reproducible, pinned Emacs binary in the Nix store

The PID1 binary must be **fully statically linked** — nixpkgs' Emacs is
dynamically linked, so `overrideAttrs` is not suitable here. The derivation
builds all six C dependencies (ncurses, GMP, nettle, GnuTLS, libxml2,
tree-sitter) as static archives from source. See `pkgs/emacs-pid1/default.nix`.

Note: `overrideAttrs` on nixpkgs' emacs *is* the right approach for the
separate **graphical Emacs** needed in Milestone 1.5 (EXWM desktop session),
where dynamic linking against X11/GTK is correct and desired.

This derivation is the critical path — everything else is blocked on it.

**Deliverable:** `nix build .#emacs-elinit` produces a working patched Emacs binary.

### Milestone 1.2 — Bootable VM Image

A minimal Nix system configuration that:

- Generates a bootable disk image (via `system.build.diskImage` or equivalent)
- Boots with GRUB or systemd-boot to the Linux kernel
- Has the patched Emacs binary available in the environment
- Boots to a root shell (no Emacs as PID 1 yet, just prove the boot chain)

This validates the Nix build system and disk image pipeline before any
el-init complexity is introduced.

**Deliverable:** A VM image that boots and provides a shell with patched Emacs available.

### Milestone 1.3 — El-init as PID 1

Following el-init's `static-builds/` instructions inside the Nix derivation:

- Emacs is the kernel's init process (PID 1)
- El-init starts and manages basic services
- Zombie reaping works correctly (el-init's PID 1 patchset)
- The Emacs server is started so `emacsclient` / `elinitctl` work

El-init unit files for this milestone live in `/etc/elinit.el/` (system tier)
and are generated by Nix — not hand-written files.

**Deliverable:** VM boots to Emacs as PID 1 with el-init running. `elinitctl status` works.

### Milestone 1.4 — Core System Services

El-init unit files (generated by Nix derivations) for:

- **D-Bus daemon** — required by most desktop services
- **PipeWire** — audio, replacing PulseAudio
- **WirePlumber** — PipeWire session manager
- **NetworkManager** — networking
- **Xorg** — X11 display server, member of `graphical.target`

All services defined display-stack-agnostically. `graphical.target` is
provided by Xorg in this phase but the target itself is generic.

**Deliverable:** All services start cleanly. Audio and networking work.

### Milestone 1.5 — EXWM Desktop

- EXWM loads and manages X11 windows
- vterm available for terminal emulation
- A baseline `init.el` / system Emacs config that constitutes the desktop:
  - EXWM workspace configuration
  - Keybindings for common operations
  - A minimal status bar (using EXWM's built-in or a lightweight package)
  - El-init dashboard accessible via keybinding

**Deliverable:** A graphical desktop session. Can open terminals, run X11 apps,
manage windows.

### Milestone 1.6 — Login and Session Management

- A minimal login mechanism (either auto-login as a single user, or a simple
  Elisp login screen rendered in a framebuffer console before X starts)
- Screen lock (slock or an Elisp-based locker)
- Suspend/resume hooks in el-init (power button, lid close)
- PAM integration for the privileged bits (via el-init's `elinit-runas` helper)

**Deliverable:** System can be locked, suspended, and resumed correctly.

### Milestone 1.7 — Nix Package Management Integration

- Nix available as a user-facing package manager
- Elisp frontend for common Nix operations (search, install, remove) so users
  need not drop to a terminal for package management
- `nix-collect-garbage` as an el-init timer unit (scheduled cleanup)
- Nix flake-based system configuration so the entire OS is defined in one repo

**Deliverable:** Users can manage software from within Emacs. System is
fully described by a Nix flake.

### Milestone 1.8 — Polish and Daily Driver Stability

- Multi-monitor support via EXWM and xrandr
- Notifications daemon (either dunst as an el-init service, or a simple
  Elisp D-Bus notification listener)
- Bluetooth management frontend (Elisp D-Bus wrapper around BlueZ)
- Audio volume control (Elisp PipeWire/PulseAudio interface)
- HiDPI support
- Printer support (CUPS as an el-init service)

**Deliverable:** System is usable as a daily driver on real hardware.

---

## Phase 2: Native OpenGL Compositor

Phase 2 runs in parallel with Phase 1 polish. The compositor is developed
as a separate project and integrated once stable, without disrupting the
working Phase 1 system.

### Milestone 2.1 — Emacs-gl: GBM/EGL Support

Extend the emacs-gl C module to support creating an OpenGL context directly
on a DRM device without a display server:

- Add EGL platform support via `eglGetPlatformDisplayEXT` with
  `EGL_PLATFORM_GBM_KHR`
- Add GBM (Generic Buffer Management) surface creation
- Add DRM/KMS page-flip support for vsync-correct display
- This requires approximately 500-1000 lines of additional C in `gl-module.c`
  and `gui.cpp`

The goal is to call `(glarea-new ...)` and get a fullscreen OpenGL context
on a bare DRM device, with no X or Wayland server involved.

**Deliverable:** `emacs-gl-drm` module that opens a framebuffer via DRM/KMS/GBM/EGL.

### Milestone 2.2 — Evdev Input Module

A new Emacs dynamic module that:

- Reads raw input events from `/dev/input/eventN` via libinput
- Translates keyboard events into Emacs input events
- Translates pointer events into Emacs mouse events
- Handles multi-seat and hotplug via udev

This replaces X11's input handling. Approximately 800-1200 lines of C.

**Deliverable:** Keyboard and mouse input works without X11.

### Milestone 2.3 — Framebuffer Proof of Concept

Combine Milestone 2.1 and 2.2: boot Emacs with no display server, open a
DRM framebuffer, render Emacs's own UI via emacs-gl, accept keyboard input
via the evdev module. Emacs buffers and the minibuffer render and are
interactive.

No window management yet — just Emacs's own interface on a bare framebuffer.

**Deliverable:** Emacs renders to the screen and accepts input without X11.

### Milestone 2.4 — Minimal Wayland Compositor

An Elisp Wayland compositor using libwayland (wrapped as a C module or
driven via a subprocess):

- Implements the core Wayland protocol (wl_compositor, wl_surface,
  wl_shm, xdg_shell)
- Composites client window buffers as OpenGL textures via emacs-gl
- Handles basic window placement (tiling, initially)
- XWayland support for legacy X11 applications

The compositor logic — which windows are visible, where they appear, how
they are decorated — is pure Elisp. The C layer only handles the Wayland
protocol wire format and buffer import.

**Deliverable:** Can run a Wayland-native application (e.g. foot terminal) and an
X11 application via XWayland.

### Milestone 2.5 — ImGui System Chrome

Use emacs-gl's ImGui integration for system UI elements rendered directly
in OpenGL:

- System tray / status bar
- Notification popups
- Application launcher overlay
- Session lock screen

These are rendered as ImGui windows in the compositor's render pass, above
the composited application layer.

**Deliverable:** A complete system chrome without any dependency on X11 toolkits.

### Milestone 2.6 — Compositor Integration and Cutover

- Add compositor as an el-init service, member of `graphical.target`
- Disable Xorg service
- Validate all Phase 1 functionality works under the compositor:
  - Audio, networking, package management
  - All el-init service definitions unchanged (display-stack agnosticism
    from Phase 1 design pays off here)
- Performance tuning: frame pacing, GPU memory management, input latency

**Deliverable:** Full system running on the native compositor. X11 dependency eliminated.

---

## Nix Repository Structure

```
emacs-os/
├── flake.nix                    # System flake entry point
├── flake.lock
├── pkgs/
│   ├── emacs-elinit/            # Patched Emacs derivation
│   │   ├── default.nix
│   │   └── patches/
│   │       ├── elinit-pid1.patch
│   │       └── glarea.patch
│   └── emacs-gl-drm/            # Extended emacs-gl with DRM/KMS (Phase 2)
│       └── default.nix
├── modules/
│   ├── elinit/                  # Nix module that generates el-init unit files
│   │   ├── default.nix
│   │   └── units/               # Per-service unit generators
│   │       ├── dbus.nix
│   │       ├── pipewire.nix
│   │       ├── networkmanager.nix
│   │       ├── xorg.nix         # Phase 1
│   │       └── compositor.nix   # Phase 2
│   └── desktop/
│       └── default.nix          # Emacs config, EXWM setup
├── system/
│   └── configuration.nix        # Top-level system configuration
└── home/
    └── emacs/
        └── init.el              # System-level Emacs config
```

The `elinit` Nix module is the key design element: it takes service
descriptions as Nix attribute sets and outputs `.el` unit files into
`/etc/elinit.el/`. This is the Nix equivalent of NixOS's systemd module
system, adapted for el-init's plist format.

---

## El-init Service File Conventions

All system service unit files are generated by Nix into `/etc/elinit.el/`.
Users may override any service in `~/.config/elinit.el/` following el-init's
standard authority model.

Services must follow these conventions for display-stack agnosticism:

- Services that require a display must declare `:wanted-by ("graphical.target")`
  or `:required-by ("graphical.target")`, never a dependency on Xorg or the
  compositor directly
- The display server (Xorg in Phase 1, compositor in Phase 2) declares
  `:required-by ("graphical.target")`
- Input and audio services declare `:required-by ("multi-user.target")`

Example of correct display-agnostic service definition:

```elisp
;; nm-applet.el — correct: depends on graphical.target, not on Xorg
(:id "nm-applet"
 :command "nm-applet"
 :type simple
 :wanted-by ("graphical.target")
 :restart always)
```

---

## Risk Areas

**Patch maintenance.** The patched Emacs (el-init PID 1 patches + GLArea
patches) must track upstream Emacs releases. Patch conflicts are the most
likely source of ongoing maintenance burden. Keeping the patch surface minimal
and upstreaming where possible reduces this risk.

**Emacs as PID 1 stability.** If Emacs crashes as PID 1, the machine is
unrecoverable without a hard reset. El-init's static build is specifically
designed for this but it is an unusual operational mode. A serial console
or a secondary minimal rescue init should be considered for the long term.

**Phase 2 Wayland protocol complexity.** The Wayland protocol has many
extensions (presentation-time, linux-dmabuf, fractional scaling, etc.) that
applications increasingly depend on. A minimal compositor will work for
simple apps but may have compatibility gaps with complex applications. Budget
significant time for protocol compliance work.

**GIL / event loop interaction.** Emacs has a single-threaded event loop.
The compositor's render loop, Wayland client event handling, and evdev input
polling all need to coexist with Emacs's own scheduler without starvation.
The emacs-gl xwidget approach (callbacks driven by Emacs's event loop) may
need extension for the tight render loop a compositor requires.

---

## Prior Art and References

- **el-init** — github.com/emacs-os/el-init — PID 1 patchset and service supervisor
- **emacs-gl** — github.com/Jimx-/emacs-gl — OpenGL bindings, GLArea xwidget, ImGui
- **EXWM** — github.com/emacs-exwm/exwm — X11 window manager in Elisp
- **NixOS** — nixos.org — Closest existing system to the Nix integration model
- **Guix System** — guix.gnu.org — Full OS in a Lisp-family language; best roadmap reference
- **Weston** — gitlab.freedesktop.org/wayland/weston — Reference Wayland compositor architecture
- **Symbolics** — Lisp Machine historical reference for the Lisp-as-OS philosophy
