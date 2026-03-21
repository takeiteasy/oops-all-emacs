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
    in {
      packages.${system} = {
        emacs-pid1 = pkgs.callPackage ./pkgs/emacs-pid1 { inherit el-init; };
        elinit = pkgs.callPackage ./pkgs/elinit { inherit el-init; };
        elinit-libexec = pkgs.callPackage ./pkgs/elinit-libexec { inherit el-init; };
        # The built NixOS system closure. Use scripts/run-vm.sh to launch with
        # macOS QEMU: nix build .#vm && ./scripts/run-vm.sh ./result
        vm = self.nixosConfigurations.emacs-os-vm.config.system.build.toplevel;
      };

      nixosConfigurations.emacs-os-vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./system/vm.nix
          {
            _module.args = {
              emacs-pid1 = self.packages.${system}.emacs-pid1;
              elinit = self.packages.${system}.elinit;
              elinit-libexec = self.packages.${system}.elinit-libexec;
            };
          }
        ];
      };
    };
}
