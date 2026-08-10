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

  # escrcpy: GUI front-end for scrcpy (Android screen mirroring), distributed
  # only as an AppImage. Single source of truth — to update, bump `version` and
  # refresh `hash` (nix store prefetch-file <url>); the download URL and both
  # appimageTools passes derive from them. The asset name has tracked
  # `Escrcpy-<version>-linux-x86_64.AppImage` across releases — verify it still
  # holds at https://github.com/viarotel-org/escrcpy/releases when bumping.
  escrcpy =
    let
      version = "2.11.1";
      src = prev.fetchurl {
        url = "https://github.com/viarotel-org/escrcpy/releases/download/v${version}/Escrcpy-${version}-linux-x86_64.AppImage";
        hash = "sha256-JN+Int2G0ZnGY7XTl56pqTTdx9AX9369Ijbc+t504Pc=";
      };
      appimageContents = prev.appimageTools.extractType2 {
        pname = "escrcpy";
        inherit version src;
      };
    in
    prev.appimageTools.wrapType2 {
      pname = "escrcpy";
      inherit version src;
      extraInstallCommands = ''
        install -m 444 -D ${appimageContents}/escrcpy.desktop $out/share/applications/escrcpy.desktop
        substituteInPlace $out/share/applications/escrcpy.desktop \
          --replace-warn 'Exec=AppRun' 'Exec=escrcpy'
        cp -r ${appimageContents}/usr/share/icons $out/share/icons
      '';
    };

  # openwhispr: privacy-first voice-to-text dictation (whisper.cpp + sherpa-onnx
  # bundled in-app, so no runtime Python/pip needed), distributed only as an
  # AppImage. Same single-source-of-truth shape as escrcpy above — bump `version`
  # and refresh `hash` (nix store prefetch-file <url>) to update; the URL and both
  # appimageTools passes derive from them. The asset name has followed
  # `OpenWhispr-<version>-linux-x86_64.AppImage`; verify it still holds at
  # https://github.com/OpenWhispr/openwhispr/releases when bumping.
  openwhispr =
    let
      version = "1.7.5";
      src = prev.fetchurl {
        url = "https://github.com/OpenWhispr/openwhispr/releases/download/v${version}/OpenWhispr-${version}-linux-x86_64.AppImage";
        hash = "sha256-InmwYfIw+CfvCYx2DwZDIS9l/yj+MK5m7AUoT0TvbO4=";
      };
      appimageContents = prev.appimageTools.extractType2 {
        pname = "openwhispr";
        inherit version src;
      };
    in
    prev.appimageTools.wrapType2 {
      pname = "openwhispr";
      inherit version src;
      extraInstallCommands = ''
        install -m 444 -D ${appimageContents}/open-whispr.desktop $out/share/applications/open-whispr.desktop
        substituteInPlace $out/share/applications/open-whispr.desktop \
          --replace-warn 'Exec=AppRun' 'Exec=openwhispr'
        cp -r ${appimageContents}/usr/share/icons $out/share/icons
      '';
    };

  # gruvbox-material-gtk-theme: removed from nixpkgs on 2026-07-22 as collateral
  # damage from the gtk-engine-murrine removal (murrine is a GTK *2* engine that
  # was unmaintained upstream). Only the theme's `gtk-2.0/main.rc` ever
  # referenced murrine — the GTK3 and GTK4 halves are plain CSS — so the theme
  # is re-vendored here with the GTK2 variant pruned. GTK2 apps fall back to
  # Raleigh, which costs nothing on a host that installs no GTK2 apps.
  # To update: bump `rev`, then refresh `hash`
  # (nix-prefetch-git https://github.com/TheGreatMcPain/gruvbox-material-gtk).
  gruvbox-material-gtk-theme = prev.stdenvNoCC.mkDerivation {
    pname = "gruvbox-material-gtk-theme";
    version = "0-unstable-2025-01-16";

    src = prev.fetchFromGitHub {
      owner = "TheGreatMcPain";
      repo = "gruvbox-material-gtk";
      rev = "bb306ae972273cbfcbf78f8b772662e8b0678d82";
      hash = "sha256-F3jVvibeov/3ZlIu+m0SmNsX6l1UwunTFKy+CnAOwok=";
    };

    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/themes
      cp -r themes/* $out/share/themes/
      # Same self-announcing spirit as `--replace-fail` above: the unquoted glob
      # is left literal when it matches nothing, so `rm` fails the build the day
      # upstream stops shipping gtk-2.0 and this pruning can be deleted.
      rm -r $out/share/themes/*/gtk-2.0
      runHook postInstall
    '';

    meta = with prev.lib; {
      description = "Gruvbox Material GTK theme (GTK3/GTK4 only, murrine-free)";
      homepage = "https://github.com/TheGreatMcPain/gruvbox-material-gtk";
      license = licenses.gpl3Only;
      platforms = platforms.all;
    };
  };
}
