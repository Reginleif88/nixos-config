{
  description = "NixOS configuration";

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

    hyprland.url = "github:hyprwm/Hyprland";

    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };

    dwproton.url = "github:imaviso/dwproton-flake";

    quickshell = {
      url = "github:quickshell-mirror/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };


    zen-browser.url = "github:youwen5/zen-browser-flake";

    nix-flatpak.url = "github:gmodena/nix-flatpak";

    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    ascii-vault = {
      url = "github:lorediggia/ascii-vault";
      flake = false;
    };

    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      system = "x86_64-linux";

      commonOverlays = [
        inputs.nix-vscode-extensions.overlays.default
        (import ./overlays/default.nix {
          ascii-vault-src = inputs.ascii-vault;
          inherit (inputs) fenix;
          inherit system;
        })
      ];

      mkHost = hostname: hostDir: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          hostDir
          inputs.nix-flatpak.nixosModules.nix-flatpak
          { nixpkgs.overlays = commonOverlays; }
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";
            home-manager.extraSpecialArgs = { inherit inputs; hostname = hostname; };
            home-manager.users.reginleif88 = import ./home;
          }
        ];
      };
    in
    {
      nixosConfigurations.hyacinth = mkHost "hyacinth" ./hosts/desktop;
      nixosConfigurations.wisteria = mkHost "wisteria" ./hosts/thinkpad;
      nixosConfigurations.clematis = mkHost "clematis" ./hosts/vm;
    };
}
