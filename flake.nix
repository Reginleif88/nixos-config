{
  description = "NixOS desktop configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dwproton.url = "github:imaviso/dwproton-flake";

    quickshell.url = "github:quickshell-mirror/quickshell";

    zen-browser.url = "github:youwen5/zen-browser-flake";

    claude-code.url = "github:sadjow/claude-code-nix";

    elephant.url = "github:abenz1267/elephant";

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.desktop = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/desktop
          inputs.nix-flatpak.nixosModules.nix-flatpak
          { nixpkgs.overlays = [ inputs.nix-vscode-extensions.overlays.default ]; }
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.reginleif88 = import ./home;
          }
        ];
      };
    };
}
