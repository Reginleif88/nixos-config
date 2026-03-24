{ ... }:

{
  # Firewall
  networking.firewall.enable = true;

  # GNOME Keyring for secret storage + PAM auto-unlock
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;
}
