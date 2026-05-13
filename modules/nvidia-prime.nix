{ config, lib, pkgs, ... }:

{
  # NVIDIA proprietary drivers (PRIME offload — Intel iGPU primary)
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    # finegrained runtime PM (auto-suspend dGPU to D3cold when idle, resume on
    # access) deadlocks on this ThinkPad's BIOS — every wake calls the AML
    # _PGON / NVPO routines, which hit an infinite loop and abort with
    # AE_AML_LOOP_TIMEOUT, leaving the dGPU stuck mid-resume and freezing
    # userspace. Keep the dGPU in D0 always until BIOS is updated.
    powerManagement.finegrained = false;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;

    # PRIME offload: Intel iGPU renders by default, NVIDIA on demand
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # Hardware acceleration (Intel + NVIDIA)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [ intel-media-driver ];
  };

  # VRAM preservation across suspend/hibernate
  boot.kernelParams = [ "nvidia.NVreg_PreserveVideoMemoryAllocations=1" ];
}
