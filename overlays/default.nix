# Custom package overlays
final: prev: {
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
