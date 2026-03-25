{ pkgs, ... }:

{
  # KVM / QEMU / libvirt
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
      #ovmf.enable = true;
      #ovmf.packages = [ pkgs.OVMFFull.fd ];
    };
  };

  # Virt-manager
  programs.virt-manager.enable = true;
  environment.systemPackages = with pkgs; [
    virt-viewer
    dnsmasq
    bridge-utils
    iptables
    netcat-openbsd
    dmidecode
    swtpm
    freerdp
    podman-compose
  ];

  # Polkit rule for passwordless virt-manager access
  environment.etc."polkit-1/rules.d/50-libvirt.rules".text = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.libvirt.unix.manage" &&
          subject.isInGroup("libvirt")) {
        return polkit.Result.YES;
      }
    });
  '';

  # Default NAT network auto-start
  systemd.services.libvirt-default-network = {
    description = "Start libvirt default NAT network";
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.libvirt}/bin/virsh net-start default 2>/dev/null || true
      ${pkgs.libvirt}/bin/virsh net-autostart default 2>/dev/null || true
    '';
  };

  # Default storage pool for virt-manager
  systemd.services.libvirt-default-pool = {
    description = "Create libvirt default storage pool";
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /var/lib/libvirt/images
      ${pkgs.libvirt}/bin/virsh pool-info default 2>/dev/null && exit 0
      ${pkgs.libvirt}/bin/virsh pool-define-as default dir --target /var/lib/libvirt/images
      ${pkgs.libvirt}/bin/virsh pool-start default
      ${pkgs.libvirt}/bin/virsh pool-autostart default
    '';
  };

  # Nested virtualisation (Intel)
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModprobeConfig = "options kvm_intel nested=1";

  # Docker
  virtualisation.docker.enable = true;

  # Podman
  virtualisation.podman = {
    enable = true;
    dockerCompat = false;
  };
}
