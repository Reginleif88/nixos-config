{
  pkgs,
  inputs,
  lib,
  ...
}:

let
  windowsInstallBat = pkgs.writeText "windows-install.bat" ''
    @echo off
    setlocal

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0configure-documents.ps1"
  '';
  windowsConfigureDocuments = pkgs.writeText "configure-documents.ps1" ''
    $ErrorActionPreference = "Stop"

    $sharePath = "\\host.lan\Data"
    $timeZone = "Romance Standard Time"
    $documentsGuid = "{FDD39AD0-238F-46AF-ADB4-6C85480369C7}"

    tzutil.exe /s $timeZone

    $userShellFolders = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
    $shellFolders = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"

    New-Item -Path $userShellFolders -Force | Out-Null
    New-Item -Path $shellFolders -Force | Out-Null

    New-ItemProperty -Path $userShellFolders -Name "Personal" -PropertyType ExpandString -Value $sharePath -Force | Out-Null
    New-ItemProperty -Path $userShellFolders -Name $documentsGuid -PropertyType ExpandString -Value $sharePath -Force | Out-Null
    Set-ItemProperty -Path $shellFolders -Name "Personal" -Value $sharePath
    Set-ItemProperty -Path $shellFolders -Name $documentsGuid -Value $sharePath

    $desktop = [Environment]::GetFolderPath("Desktop")
    if ($desktop) {
        $shortcut = Join-Path $desktop "Documents.lnk"
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($shortcut)
        $link.TargetPath = $sharePath
        $link.Save()
    }

    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
  '';
  windowsOem = pkgs.runCommand "windows-oem" { } ''
    install -Dm644 ${windowsInstallBat} "$out/install.bat"
    install -Dm644 ${windowsConfigureDocuments} "$out/configure-documents.ps1"
  '';
in
{
  imports = [
    ../../modules/common.nix
    ../../modules/core.nix
    ../../modules/desktop.nix
    ../../modules/security.nix
    ../../modules/desktop-security.nix
    ../../modules/antivirus.nix
    ../../modules/login.nix
    ../../modules/services.nix
    ../../modules/nvidia.nix
    ../../modules/hyprland.nix
    ../../modules/virtualisation.nix
    ../../modules/gaming.nix
    ../../modules/huion-ble.nix
    ../../modules/github-repo-clone.nix
  ];

  # CachyOS kernel (BORE scheduler, sched-ext, BBRv3, x86-64-v3)
  nixpkgs.overlays = [
    inputs.nix-cachyos-kernel.overlays.pinned
  ];
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-bore;

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Cap kernels kept on the 1 GB ESP. Without this, systemd-boot copies a
  # kernel + (fat NVIDIA) initrd per generation and eventually fills /boot,
  # failing the bootloader install with ENOSPC. This limits ESP entries only;
  # Nix profile generations are retained independently until GC.
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.systemd-boot.editor = false;

  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";

  # Networking
  networking.hostName = "hyacinth";
  networking.networkmanager.enable = true;

  # Workstation-specific group memberships (universals come from modules/common.nix)
  users.users.reginleif88.extraGroups = [
    "libvirtd"
    "kvm"
    "docker"
  ];

  # Windows 11 VM managed by Docker (dockur/windows).
  virtualisation.oci-containers = {
    backend = "docker";
    containers.windows = {
      autoStart = false;
      image = "dockurr/windows";
      environment = {
        VERSION = "11";
        RAM_SIZE = "16G";
        CPU_CORES = "6";
        CPU_MODEL = "host";
        DISK_SIZE = "256G";
        ALLOCATE = "Y";
        ARGUMENTS = "-rtc base=localtime";
        SAMBA = "Y";
      };
      devices = [
        "/dev/kvm:/dev/kvm"
        "/dev/net/tun:/dev/net/tun"
      ];
      ports = [
        "127.0.0.1:8006:8006"
        "127.0.0.1:3389:3389/tcp"
        "127.0.0.1:3389:3389/udp"
      ];
      volumes = [
        "/var/lib/windows:/storage"
        "/home/reginleif88/Documents:/shared"
        "${windowsOem}:/oem:ro"
      ];
      extraOptions = [
        "--cap-add=NET_ADMIN"
        "--stop-timeout=120"
      ];
    };
  };

  systemd.tmpfiles.rules = [ "d /var/lib/windows 0750 root docker -" ];
  systemd.services.docker-windows.serviceConfig.Restart = lib.mkForce "on-failure";

  sops.secrets = {
    "github_token" = {
      owner = "reginleif88";
    };
    "github_repos" = {
      owner = "reginleif88";
    };
    "zlm_api_key" = {
      owner = "reginleif88";
    };
    "gtasks_client_id" = {
      owner = "reginleif88";
    };
    "gtasks_client_secret" = {
      owner = "reginleif88";
    };
    "keyring_password" = {
      owner = "reginleif88";
    };
  };

  # Disable unwanted ALSA audio devices (NVIDIA GPU HDMI, Corsair ST100)
  services.pipewire.wireplumber.extraConfig."51-disable-unwanted-audio" = {
    "monitor.alsa.rules" = [
      {
        matches = [
          { "device.description" = "~GP104.*"; }
          { "device.description" = "~.*ST100.*"; }
        ];
        actions = {
          "update-props" = {
            "device.disabled" = true;
          };
        };
      }
    ];
  };

  # Auto-connect Edifier R1280DBs on login
  systemd.user.services.bt-connect-edifier = {
    description = "Auto-connect Edifier R1280DBs Bluetooth speaker";
    after = [ "bluetooth.target" ];
    wants = [ "bluetooth.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bluez}/bin/bluetoothctl connect 08:F0:B6:51:73:7E";
      Restart = "on-failure";
      RestartSec = 5;
      RestartMaxDelaySec = 30;
    };
  };

  system.stateVersion = "25.11";
}
