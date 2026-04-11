{ pkgs, inputs, ... }:

let
  src = inputs.huion-note-x10-ble;

  python = pkgs.python3.withPackages (ps: [ ps.dbus-fast ]);

  # Patch BlueZ to tolerate duplicate ATT requests from the Huion Note X10.
  # The device firmware sends 9 rapid-fire Exchange MTU Requests after every
  # connection parameter update. Unpatched BlueZ disconnects on the duplicate.
  bluez-patched = pkgs.bluez.overrideAttrs (old: {
    patches = (old.patches or []) ++ [
      "${src}/patches/fix-duplicate-mtu-request.patch"
    ];
  });

  huion-ble-driver = pkgs.stdenv.mkDerivation {
    pname = "huion-note-x10-ble-driver";
    version = "0.1.0";

    inherit src;

    # Source is a fetchGit directory, no archive to unpack
    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/bin $out/lib/udev/rules.d

      # Install the driver script
      cp ${src}/huion_ble_driver.py $out/bin/huion-ble-driver
      chmod +x $out/bin/huion-ble-driver
      substituteInPlace $out/bin/huion-ble-driver \
        --replace-fail "#!/usr/bin/env python3" "#!${python}/bin/python3"

      # Install udev rules from upstream
      cp ${src}/99-huion-note-x10.rules $out/lib/udev/rules.d/
    '';

    meta = with pkgs.lib; {
      description = "Huion Note X10 BLE tablet driver (reverse-engineered)";
      license = licenses.mit;
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  environment.systemPackages = [ huion-ble-driver ];

  services.udev.packages = [ huion-ble-driver ];

  # Kernel modules for userspace input injection
  boot.kernelModules = [ "uinput" ];

  # User needs input group for /dev/uinput access
  users.users.reginleif88.extraGroups = [ "input" ];

  # Use patched BlueZ that tolerates duplicate ATT requests
  hardware.bluetooth.package = bluez-patched;

  # Systemd user service — auto-starts after Bluetooth is ready
  systemd.user.services.huion-ble = {
    description = "Huion Note X10 BLE tablet driver";
    after = [ "bluetooth.target" "graphical-session.target" ];
    wants = [ "bluetooth.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${huion-ble-driver}/bin/huion-ble-driver";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
