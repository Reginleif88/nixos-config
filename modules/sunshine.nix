{ config, pkgs, lib, ... }:

{
  options.modules.sunshine.useCuda = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Build Sunshine with CUDA/NVENC support for NVIDIA hosts (default).
      Set to false on AMD hosts so Sunshine builds with VAAPI/AMF
      hardware encoding instead.
    '';
  };

  config = {
    # Sunshine needs /dev/uinput to inject mouse/keyboard input via virtual
    # devices. The host config must also add the user that runs Sunshine to
    # the `uinput` group, otherwise every virtual device creation returns
    # EACCES and inputs from the Moonlight client are silently dropped.
    hardware.uinput.enable = true;

    # Sunshine game streaming host (Moonlight-compatible)
    services.sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;  # Required for Wayland/KMS capture
      openFirewall = true; # TCP 47984-47990, UDP 47998-48000

      # NVIDIA hosts: build with CUDA for proper NVENC hardware encoding.
      # Without it, Sunshine's encoder probe requests multi-ref features
      # that Pascal (GTX 1080) doesn't support, falling back to software
      # encoding. cudaSupport also adds autoAddDriverRunpath, solving
      # the libcuda.so.1 discovery issue through the setcap wrapper.
      #
      # AMD hosts: use the default build, which links VAAPI/AMF and works
      # with mesa. cudaSupport on AMD would link CUDA the encoder cannot
      # use and break the probe.
      package =
        if config.modules.sunshine.useCuda
        then pkgs.sunshine.override { cudaSupport = true; }
        else pkgs.sunshine;
    };
  };
}
