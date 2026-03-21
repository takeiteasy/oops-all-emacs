# Milestone 1.2: Bootable QEMU VM
#
# A minimal NixOS system that boots to a root shell with the PID1-patched
# Emacs available. Standard systemd is still PID 1 at this stage — the
# purpose is to validate the boot chain and confirm the Emacs binary works.
#
# Usage:
#   nix build .#vm && ./scripts/run-vm.sh ./result
#
# Inside the VM:
#   emacs --version                          → 30.2
#   emacs --pid1 --batch -Q \
#     --eval '(message "%s" pid1-mode)'      → t

{ config, pkgs, lib, emacs-pid1, elinit, elinit-libexec, ... }:

{
  system.stateVersion = "25.05";
  networking.hostName = "emacs-os";

  # Skip docs and other heavy optional packages to keep image small
  documentation.enable = false;
  documentation.nixos.enable = false;

  environment.systemPackages = [
    emacs-pid1
    elinit
    elinit-libexec
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
  # Several NixOS modules produce empty buildEnv derivations (firmware,
  # console-env, etc.) that fail because builder.pl doesn't create the
  # output directory when there are no input paths. Provide stubs.
  hardware.firmware = lib.mkForce [
    (pkgs.runCommand "empty-firmware" {} "mkdir -p $out/lib/firmware")
  ];

  # Disable console font/keymap setup — not needed for serial console VM
  console.font = null;
  console.keyMap = lib.mkDefault "us";

  # Disable i18n glyphs (prevents empty console-env buildEnv)
  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];
}
