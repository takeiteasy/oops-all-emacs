{
  description = "Emacs-OS: GNU Emacs as PID 1";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    el-init = {
      url = "github:emacs-os/el-init";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, el-init }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      make-disk-image = import (pkgs.path + "/nixos/lib/make-disk-image.nix");
      specialArgs = {
        emacs-pid1 = self.packages.${system}.emacs-pid1;
        elinit = self.packages.${system}.elinit;
        elinit-libexec = self.packages.${system}.elinit-libexec;
        emacs-graphical = self.packages.${system}.emacs-graphical;
      };
    in {
      packages.${system} = {
        emacs-pid1 = pkgs.callPackage ./pkgs/emacs-pid1 { inherit el-init; };
        elinit = pkgs.callPackage ./pkgs/elinit { inherit el-init; };
        elinit-libexec = pkgs.callPackage ./pkgs/elinit-libexec { inherit el-init; };
        emacs-graphical = pkgs.callPackage ./pkgs/emacs-graphical {};
        # The built NixOS system closure. Use scripts/run-vm.sh to launch with
        # macOS QEMU: nix build .#vm && ./scripts/run-vm.sh ./result
        vm = self.nixosConfigurations.emacs-os-vm.config.system.build.toplevel;

        # A qcow2 disk image containing the Nix store (replaces 9p share).
        # Boots via scripts/run-disk-vm.sh on macOS QEMU.
        # Build: nix build .#disk-image
        disk-image = make-disk-image {
          inherit (pkgs) lib;
          pkgs = pkgs;
          config = self.nixosConfigurations.emacs-os-disk.config;
          diskSize = "auto";
          format = "qcow2";
          partitionTableType = "none";
          onlyNixStore = true;
          installBootLoader = false;
          name = "emacs-os-nix-store";
        };

        # System closure for disk-boot (kernel, initrd with ext4/virtio_blk).
        # Use alongside disk-image: nix build .#disk-closure
        disk-closure = self.nixosConfigurations.emacs-os-disk.config.system.build.toplevel;
      };

      nixosConfigurations.emacs-os-vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./system/vm.nix
          { _module.args = specialArgs; }
        ];
      };

      # Disk-boot variant: nix store on a block device instead of 9p
      nixosConfigurations.emacs-os-disk = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./system/disk.nix
          { _module.args = specialArgs; }
        ];
      };
    };
}
