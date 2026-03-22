# Emacs-OS QEMU VM configuration
#
# Milestones 1.2 + 1.3: Bootable QEMU VM with el-init as PID 1.
# NixOS handles Stage 1 (initrd) and Stage 2 (activation scripts),
# then execs into emacs-pid1 --pid1 instead of systemd.
#
# Usage:
#   nix build .#vm && ./scripts/run-vm.sh ./result
#
# Inside the VM:
#   ps -p 1 -o comm=                            → emacs
#   elinitctl status                             → shows running services
#   emacs --pid1 --batch -Q \
#     --eval '(message "%s" pid1-mode)'          → t

{ config, pkgs, lib, emacs-pid1, elinit, elinit-libexec, ... }:

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
    pkgs.procps      # ps, top — needed for verification
  ];

  # Make el-init Elisp discoverable on Emacs load-path
  environment.pathsToLink = [ "/share/emacs" ];

  # Auto-login root for development convenience
  services.getty.autologinUser = "root";
  users.users.root.initialPassword = "emacs";

  # Root filesystem: tmpfs (stateless VM, no persistent disk needed yet)
  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "mode=0755" "size=1G" ];
  };

  # Mount the host's /nix/store via 9p so the initrd can find the stage 2
  # init script and all Nix store paths. The QEMU script shares /nix/store
  # as the "nix-store" 9p tag.
  fileSystems."/nix/store" = {
    device = "nix-store";
    fsType = "9p";
    options = [ "trans=virtio" "version=9p2000.L" "cache=loose" "ro" ];
    neededForBoot = true;
  };

  # No bootloader — kernel is loaded directly by QEMU -kernel flag
  boot.loader.grub.enable = false;

  # Serial console for headless QEMU
  boot.kernelParams = [ "console=ttyAMA0,115200n8" ];

  # Ensure 9p modules are in the initrd so /nix/store can be mounted early
  boot.initrd.availableKernelModules = [
    "9p" "9pnet" "9pnet_virtio" "virtio_pci" "virtio_blk"
  ];

  # ── Workarounds for building on macOS linux-builder ──────────────────────
  hardware.firmware = lib.mkForce [
    (pkgs.runCommand "empty-firmware" {} "mkdir -p $out/lib/firmware")
  ];
  console.font = null;
  console.keyMap = lib.mkDefault "us";
  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];
}
