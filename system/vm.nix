# Emacs-OS QEMU VM configuration
#
# Milestones 1.2–1.5: Bootable QEMU VM with el-init as PID 1,
# core services, and EXWM graphical desktop.
#
# Usage:
#   nix build .#packages.aarch64-linux.vm && ./scripts/run-vm.sh ./result
#   EMACS_OS_HEADLESS=1 ./scripts/run-vm.sh ./result    # headless mode
#
# Inside the VM:
#   elinitctl status                             → shows running services
#   ps -p 1 -o comm=                            → emacs

{ config, pkgs, lib, emacs-pid1, elinit, elinit-libexec, emacs-graphical, ... }:

{
  imports = [
    ./elinit-init.nix
  ];

  system.stateVersion = "25.05";
  networking.hostName = "emacs-os";

  # Skip docs and other heavy optional packages to keep image small
  documentation.enable = false;
  documentation.nixos.enable = false;

  environment.systemPackages = [
    emacs-pid1
    elinit
    elinit-libexec
    emacs-graphical
    pkgs.procps          # ps, top
    pkgs.dbus            # dbus-send, dbus-monitor
    pkgs.iproute2        # ip
    pkgs.iputils         # ping
    pkgs.xterm           # fallback terminal
    pkgs.xdpyinfo   # Xorg readiness check
  ];

  # Make el-init Elisp discoverable on Emacs load-path
  environment.pathsToLink = [ "/share/emacs" ];

  # Auto-login root for development convenience
  services.getty.autologinUser = "root";
  users.users.root.initialPassword = "emacs";

  # ── NixOS service infrastructure (config files, users, binaries) ──────

  # D-Bus system bus: creates messagebus user/group, /etc/dbus-1/ config
  services.dbus.enable = true;

  # NetworkManager: creates config, users, resolv.conf management
  networking.networkmanager.enable = true;

  # PipeWire + WirePlumber: config files, binaries
  services.pipewire.enable = true;
  services.pipewire.wireplumber.enable = true;

  # Xorg infrastructure: generates /etc/X11/xorg.conf, installs fonts,
  # sets up module paths. We start Xorg via el-init, not systemd.
  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "modesetting" ];
  services.libinput.enable = true;
  services.xserver.autorun = false;
  services.xserver.displayManager.startx.enable = true;

  # Fonts for Emacs and X11 applications
  fonts.enableDefaultPackages = true;

  # Root filesystem: tmpfs (increased for graphical session)
  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "mode=0755" "size=2G" ];
  };

  # Mount the host's /nix/store via 9p
  fileSystems."/nix/store" = {
    device = "nix-store";
    fsType = "9p";
    options = [ "trans=virtio" "version=9p2000.L" "cache=loose" "ro" ];
    neededForBoot = true;
  };

  # No bootloader — kernel is loaded directly by QEMU -kernel flag
  boot.loader.grub.enable = false;

  # Serial console for headless QEMU (also works alongside graphical)
  boot.kernelParams = [ "console=ttyAMA0,115200n8" ];

  # Force-load modules (no systemd-udevd to auto-detect devices)
  boot.kernelModules = [ "virtio_input" "virtio_gpu" ];

  # Ensure required modules are in the initrd
  boot.initrd.availableKernelModules = [
    "9p" "9pnet" "9pnet_virtio" "virtio_pci" "virtio_blk"
    "virtio_net"    # QEMU virtio networking
    "virtio_gpu"    # QEMU virtio graphics
    "virtio_input"  # QEMU virtio keyboard/tablet
    "drm"           # Direct Rendering Manager
  ];

  # ── Workarounds for building on macOS linux-builder ──────────────────────
  hardware.firmware = lib.mkForce [
    (pkgs.runCommand "empty-firmware" {} "mkdir -p $out/lib/firmware")
  ];
  console.font = null;
  console.keyMap = lib.mkDefault "us";
  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];
}
