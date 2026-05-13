# Custom package overlays
{ inputs, ... }:
final: prev:

let
  hyprlandPackage = inputs.hyprland.packages.${final.stdenv.hostPlatform.system}.hyprland;
in
{
  # Upstream Hyprland workaround against HEAD commit ee58a513 (2026-05-09).
  # `--replace-fail` makes the build error if upstream changes the matched string,
  # so the patch announces itself when it can be dropped.
  # Patches a device-tags null deref when a keyboard has no explicit device block.
  hyprland-patched = hyprlandPackage.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace src/managers/input/InputManager.cpp \
        --replace-fail 'CVarList2(Config::mgr()->getDeviceString(devname, "tags"))' 'CVarList2(std::string(""))'
    '';
  });

  gtasks = prev.buildGoModule {
    pname = "gtasks";
    version = "0.13.0";
    src = prev.fetchFromGitHub {
      owner = "BRO3886";
      repo = "gtasks";
      rev = "v0.13.0";
      hash = "sha256-MoBlKuv8Use1VRQkJizsLfsZ4F2eFsWmWElY6KwmDH0=";
    };
    # Run `nix build .#nixosConfigurations.<host>.config.home-manager.users.reginleif88.home.packages`
    # and replace with the hash from the error output.
    vendorHash = "sha256-bgg1ZAJya0NfWLLYB10egUhQXIP+A2oaQfh+CdQOOow=";
    meta = with prev.lib; {
      description = "CLI client for Google Tasks";
      homepage = "https://github.com/BRO3886/gtasks";
      license = licenses.mit;
      mainProgram = "gtasks";
    };
  };

  escrcpy = prev.appimageTools.wrapType2 {
    pname = "escrcpy";
    version = "2.6.2";
    src = prev.fetchurl {
      url = "https://github.com/viarotel-org/escrcpy/releases/download/v2.6.2/Escrcpy-2.6.2-linux-x86_64.AppImage";
      sha256 = "0mg37z9yhc5yvpf28zsr5d0m4xdm9x057s58fnvww4x7p4wclczv";
    };
    extraInstallCommands = let
      appimageContents = prev.appimageTools.extractType2 {
        pname = "escrcpy";
        version = "2.6.2";
        src = prev.fetchurl {
          url = "https://github.com/viarotel-org/escrcpy/releases/download/v2.6.2/Escrcpy-2.6.2-linux-x86_64.AppImage";
          sha256 = "0mg37z9yhc5yvpf28zsr5d0m4xdm9x057s58fnvww4x7p4wclczv";
        };
      };
    in ''
      install -m 444 -D ${appimageContents}/escrcpy.desktop $out/share/applications/escrcpy.desktop
      substituteInPlace $out/share/applications/escrcpy.desktop \
        --replace-warn 'Exec=AppRun' 'Exec=escrcpy'
      cp -r ${appimageContents}/usr/share/icons $out/share/icons
    '';
  };
}
