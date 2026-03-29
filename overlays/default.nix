# Custom package overlays
{ ascii-vault-src, ... }:
final: prev: {
  ascii-vault = prev.rustPlatform.buildRustPackage {
    pname = "ascii-vault";
    version = "1.0.0";
    src = ascii-vault-src;
    cargoHash = "sha256-+j+Si7Uafg6dv/emPtEhQxJoKz0ti9ibaRgugFM35HA=";
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

  winboat = prev.appimageTools.wrapType2 {
    pname = "winboat";
    version = "0.9.0";
    src = prev.fetchurl {
      url = "https://github.com/TibixDev/winboat/releases/download/v0.9.0/winboat-0.9.0-x86_64.AppImage";
      sha256 = "1xhf15ryad3zbm3d34gaj8n88cmmr610naxp4r00xvidpnv24lnk";
    };
    extraInstallCommands = let
      appimageContents = prev.appimageTools.extractType2 {
        pname = "winboat";
        version = "0.9.0";
        src = prev.fetchurl {
          url = "https://github.com/TibixDev/winboat/releases/download/v0.9.0/winboat-0.9.0-x86_64.AppImage";
          sha256 = "1xhf15ryad3zbm3d34gaj8n88cmmr610naxp4r00xvidpnv24lnk";
        };
      };
    in ''
      install -m 444 -D ${appimageContents}/winboat.desktop $out/share/applications/winboat.desktop
      substituteInPlace $out/share/applications/winboat.desktop \
        --replace-warn 'Exec=AppRun' 'Exec=winboat'
      cp -r ${appimageContents}/usr/share/icons $out/share/icons
    '';
  };
}
