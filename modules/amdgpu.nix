{ pkgs, ... }:

{
  # Load amdgpu early so it claims the iGPU before userspace starts
  boot.initrd.kernelModules = [ "amdgpu" ];

  # X11 driver
  services.xserver.videoDrivers = [ "amdgpu" ];

  # OpenGL + Vulkan + VAAPI runtime for hardware video decode/encode.
  # VAAPI is what Sunshine uses on AMD via the amfenc/vaapi plugin.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      libva-vdpau-driver
      libvdpau-va-gl
      vulkan-loader
      vulkan-validation-layers
    ];
  };

  # Userland diagnostics for the iGPU
  environment.systemPackages = with pkgs; [
    libva-utils      # vainfo: verifies VAAPI encoder/decoder availability
    vulkan-tools     # vulkaninfo
    radeontop        # live GPU utilization
    mesa-demos       # provides glxinfo / glxgears (renamed from glxinfo)
  ];
}
