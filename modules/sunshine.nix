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

    # Build with CUDA for proper NVENC hardware encoding on NVIDIA GPUs.
    # Without this, Sunshine's encoder probe requests multi-ref features that
    # Pascal (GTX 1080) doesn't support, falling back to software encoding.
    # cudaSupport also adds autoAddDriverRunpath, solving the libcuda.so.1
    # discovery issue through the setcap wrapper.
    package = pkgs.sunshine.override { cudaSupport = true; };
  };
}
