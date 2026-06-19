{ config, pkgs, ... }:

{
  # NVIDIA proprietary drivers
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
  };

  # Hardware acceleration
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    # VA-API-over-NVDEC bridge: translates VA-API decode calls onto Pascal's
    # NVDEC engine (paired with LIBVA_DRIVER_NAME=nvidia + NVD_BACKEND=direct
    # below). Usable by Firefox/mpv/ffmpeg. NOT usable by Chromium — it hardcodes
    # a skip for nvidia-drm devices, so google-chrome (and the `boosteroid`
    # launcher) always software-decode regardless of this driver.
    extraPackages = [ pkgs.nvidia-vaapi-driver ];
  };

  # vainfo — lists which VA-API decode/encode profiles the NVDEC bridge exposes
  # (H.264/HEVC/VP9 VLD all present on this Pascal card). Diagnostic only.
  environment.systemPackages = [ pkgs.libva-utils ];

  # VRAM preservation across suspend/hibernate
  boot.kernelParams = [ "nvidia.NVreg_PreserveVideoMemoryAllocations=1" ];

  # NVIDIA environment variables for Wayland
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    NVD_BACKEND = "direct";

    # NVIDIA legacy 580.x advertises DRM_CAP_SYNCOBJ_TIMELINE but never settles
    # the timeline points Aquamarine waits on after an atomic page-flip — every
    # subsequent commit fails with "Cannot commit when a page-flip is awaiting"
    # and the scanout pipeline stalls (compositor stays alive, screen is black,
    # Ctrl+Alt+F-key TTY switch also wedges). Surfaced by Aquamarine 0.11 (2026-05-12
    # flake.lock bump), which started honouring an advertisement 0.10 effectively
    # ignored. AQ_NO_ATOMIC=1 forces the legacy drmModeSetCrtc / drmModePageFlip
    # path which doesn't use timeline syncobjs at all. Remove once NVIDIA ships
    # a working timeline-syncobj backend on the 580 driver branch.
    AQ_NO_ATOMIC = "1";
  };
}
