{ config, pkgs, lib, emacs-pid1, elinit, elinit-libexec, emacs-graphical, ... }:

{
  imports = [ ./vm.nix ];

  # Nix store from a virtio block device instead of 9p
  fileSystems."/nix/store" = lib.mkForce {
    device = "/dev/vda";
    fsType = "ext4";
    options = [ "ro" ];
    neededForBoot = true;
  };

  # Add block device modules to initrd
  boot.initrd.availableKernelModules = lib.mkForce [
    "9p" "9pnet" "9pnet_virtio" "virtio_pci" "virtio_blk" "virtio_net"
    "virtio_gpu" "virtio_input"
    "drm"
    "ext4" "crc32c"
  ];
}
