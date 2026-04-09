{ pkgs, ... }:

let
  huion-tablet = pkgs.stdenv.mkDerivation {
    pname = "huion-tablet-driver";
    version = "15.0.0.175";

    src = ./huion/HuionTablet_LinuxDriver_v15.0.0.175.x86_64.deb;

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      makeWrapper
    ];

    # Runtime deps the ELF binaries link against (not bundled)
    buildInputs = with pkgs; [
      stdenv.cc.cc.lib # libstdc++
      libx11
      libxrandr
      libxtst
      libxext
      libxrender
      libxcb
      libxinerama
      libGL
      zlib
      fontconfig
      freetype
      libgpg-error
      e2fsprogs # libcom_err.so.2
      libusb1
      systemd
      glib
      dbus
    ];

    unpackPhase = ''
      ${pkgs.binutils}/bin/ar x $src
      tar xf data.tar.xz
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/huiontablet
      cp -r usr/lib/huiontablet/* $out/lib/huiontablet/

      # Remove bundled libs that are too old — let autoPatchelf use system versions.
      # Keeping them would poison child processes (bluetoothctl, grep, etc.)
      # via LD_LIBRARY_PATH with ancient incompatible versions.
      rm -f $out/lib/huiontablet/libs/libsystemd.so.0
      rm -f $out/lib/huiontablet/libs/libudev.so.1
      rm -f $out/lib/huiontablet/libs/libglib-2.0.so.0
      rm -f $out/lib/huiontablet/libs/libgthread-2.0.so.0
      rm -f $out/lib/huiontablet/libs/libdbus-1.so.3

      # Wrap binaries: set library paths and cd into a writable state dir
      # (the binaries write .pid/.log files relative to CWD)
      for bin in $out/lib/huiontablet/huionCore $out/lib/huiontablet/huiontablet; do
        wrapProgram "$bin" \
          --set LD_LIBRARY_PATH "$out/lib/huiontablet/libs" \
          --set QT_QPA_PLATFORM_PLUGIN_PATH "$out/lib/huiontablet/plugins" \
          --set QML2_IMPORT_PATH "$out/lib/huiontablet/qml" \
          --set QT_QPA_PLATFORM "xcb" \
          --prefix PATH : "${pkgs.lib.makeBinPath [
            pkgs.xorg.xmodmap
            pkgs.bluez        # hcitool, bluetoothctl
            pkgs.util-linux
            pkgs.gnugrep      # grep (used in BT detection pipeline)
            pkgs.gnused        # sed
            pkgs.coreutils    # cat, sleep, etc.
            pkgs.gawk         # awk
            pkgs.bash         # sh -c
          ]}" \
          --run 'STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/huiontablet"; mkdir -p "$STATE_DIR"; cd "$STATE_DIR"'
      done

      # Symlinks on PATH
      mkdir -p $out/bin
      ln -s $out/lib/huiontablet/huionCore $out/bin/huionCore
      ln -s $out/lib/huiontablet/huiontablet $out/bin/huiontablet

      # Desktop entry
      mkdir -p $out/share/applications
      cat > $out/share/applications/huiontablet.desktop <<'DESKTOP'
[Desktop Entry]
Encoding=UTF-8
Name=HuionTablet
Comment=Huion tablet driver
Exec=huiontablet
Icon=huiontablet
Terminal=false
Type=Application
Categories=Utility;
DESKTOP

      # Icon
      mkdir -p $out/share/icons/hicolor/128x128/apps
      cp usr/share/icons/huiontablet.png $out/share/icons/hicolor/128x128/apps/huiontablet.png

      # udev rules
      mkdir -p $out/lib/udev/rules.d
      cp usr/lib/udev/rules.d/20-huion.rules $out/lib/udev/rules.d/

      runHook postInstall
    '';

    meta = with pkgs.lib; {
      description = "Huion tablet driver for Linux (proprietary)";
      license = licenses.unfree;
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  environment.systemPackages = [ huion-tablet ];

  # udev rules for Huion tablet access (uhid, uinput, USB vendor 256c)
  services.udev.packages = [ huion-tablet ];

  # Extra rules for hidraw devices created by huionCore via uhid
  services.udev.extraRules = ''
    KERNEL=="hidraw*", ATTRS{idVendor}=="256c", MODE="0666"
    SUBSYSTEM=="input", ATTRS{name}=="Huion Tablet*", MODE="0666"
  '';

  # Ensure uhid and uinput modules are loaded for userspace HID injection
  boot.kernelModules = [ "uhid" "uinput" ];

  # Bluetooth HID userspace access
  hardware.bluetooth.settings = {
    General = {
      UserspaceHID = true;
    };
  };

  # Autostart huionCore daemon via systemd user service
  systemd.user.services.huion-core = {
    description = "Huion tablet core daemon";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStartPre = "-${pkgs.bash}/bin/bash -c 'rm -f \${XDG_STATE_HOME:-$HOME/.local/state}/huiontablet/.HuionCore.pid'";
      ExecStart = "${huion-tablet}/bin/huionCore";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
