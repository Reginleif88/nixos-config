{ pkgs, ... }:

{
  # Sunshine needs /dev/uinput to inject mouse/keyboard input via virtual devices
  hardware.uinput.enable = true;

  # Sunshine game streaming host (Moonlight-compatible)
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;  # Required for Wayland/KMS capture
    openFirewall = true; # TCP 47984-47990, UDP 47998-48000
  };
}
