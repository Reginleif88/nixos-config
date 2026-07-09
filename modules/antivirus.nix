{ config, lib, pkgs, ... }:

# Malware defence for the workstation, built around one specific threat:
# this PC writes files onto a *work* USB key that then enters a work network.
# The PC is the potential source of contamination, so the goal is that
# nothing ever rides onto the key unnoticed.
#
# Because USB keys get yanked without ejecting here, any control that depends
# on a "before you eject" step is useless. So we scan files AS THEY ARE WRITTEN
# to removable media (ClamAV on-access / fanotify) and block infected ones.
# Whenever the key is pulled, whatever landed on it has already been checked.
#
# Layers:
#   1. clamav-daemon + freshclam   — signature engine (carries Windows sigs too)
#   2. clamonacc on /run/media     — real-time scan + prevention on the USB path
#   3. udisks sync/flush + noexec  — immediate flush (safe yank) & no exec off keys
#   4. weekly lynis audit          — host-side rootkit/malware/hardening check
#                                    (we're the source of trust, so verify the PC
#                                    itself). rkhunter/chkrootkit were dropped from
#                                    nixpkgs as unmaintained; lynis is the
#                                    maintained equivalent.

let
  uid = "1000"; # reginleif88 — used to reach the graphical D-Bus session

  # Runs as root (clamonacc's context) and crosses into the user's session
  # to pop a critical desktop toast. Best-effort: the authoritative record is
  # always the systemd journal (see VirusEvent below).
  notifyUser = pkgs.writeShellScript "clamav-notify-user" ''
    ${pkgs.util-linux}/bin/runuser -u reginleif88 -- \
      ${pkgs.coreutils}/bin/env \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus \
        ${pkgs.libnotify}/bin/notify-send -u critical -a ClamAV \
        "⚠ ClamAV blocked a threat" "$1" || true
  '';

  # Wraps clamonacc so we can turn its detection lines into desktop toasts.
  # Prevention itself is enforced in-kernel via fanotify regardless of this.
  onAccessRunner = pkgs.writeShellScript "clamonacc-runner" ''
    set -o pipefail
    ${pkgs.clamav}/bin/clamonacc --foreground --fdpass \
      --config-file=/etc/clamav/clamd.conf 2>&1 |
    while IFS= read -r line; do
      printf '%s\n' "$line"
      case "$line" in
        *FOUND*|*blocked*) ${notifyUser} "$line" ;;
      esac
    done
  '';

  # Host integrity: lynis audits for rootkit/malware indicators (known rootkit
  # files, hidden processes, suspicious open ports, deleted-but-running
  # binaries) plus general hardening. On NixOS the read-only /nix/store already
  # makes system binaries tamper-evident, so lynis's behavioural checks are the
  # part that adds value here. --cronjob = non-interactive; full report lands in
  # /var/log/lynis-report.dat and the run summary in the journal.
  lynisCheck = pkgs.writeShellScript "lynis-check" ''
    exec ${pkgs.lynis}/bin/lynis audit system --cronjob --no-colors
  '';

  # Manual helper: scan every currently-mounted removable device on demand,
  # e.g. for a key handed to you rather than one you wrote. On-access already
  # covers the write path; this is for peace of mind.
  usbScan = pkgs.writeShellScriptBin "usb-scan" ''
    set -euo pipefail
    media="/run/media/$USER"
    if [ ! -d "$media" ] || [ -z "$(ls -A "$media" 2>/dev/null)" ]; then
      echo "No removable media mounted under $media."
      exit 0
    fi
    echo "Scanning: $media/*"
    ${pkgs.clamav}/bin/clamdscan --multiscan --fdpass -i "$media"/*
  '';
in
{
  ###########################################################################
  # 1 + 2. ClamAV: signature engine, auto-updates, and on-access scanning
  ###########################################################################
  services.clamav.daemon.enable = true;

  services.clamav.updater = {
    enable = true;
    frequency = 12;          # freshclam signature checks per day
    interval = "daily";
  };

  services.clamav.daemon.settings = {
    # Watch the removable-media mount tree. Files copied onto a USB key are
    # scanned as they are written; OnAccessPrevention denies access to any
    # file that matches a signature, so it never fully lands on the key.
    OnAccessIncludePath = "/run/media";
    OnAccessPrevention = true;
    OnAccessExtraScanning = true;       # catch creates/moves within the tree
    OnAccessExcludeUname = "clamav";    # don't scan our own reads (loop guard)
    OnAccessMaxFileSize = "256M";

    # Authoritative detection record → journal (survives even if the desktop
    # notification can't reach the session bus).
    VirusEvent = "${pkgs.writeShellScript "clamav-log-event" ''
      ${pkgs.util-linux}/bin/logger -t clamav-virus \
        "THREAT: $CLAM_VIRUSEVENT_VIRUSNAME in $CLAM_VIRUSEVENT_FILENAME"
    ''}";
  };

  # /run/media must exist at boot so clamonacc can place its fanotify mark;
  # udisks creates the per-user subdir under it on first mount.
  systemd.tmpfiles.rules = [ "d /run/media 0755 root root -" ];

  # clamonacc (the fanotify client) isn't wired up by the NixOS module, so we
  # run it ourselves. It needs clamd's socket and a populated signature DB.
  systemd.services.clamonacc = {
    description = "ClamAV on-access scanner (removable media)";
    after = [ "clamav-daemon.service" "clamav-freshclam.service" ];
    wants = [ "clamav-daemon.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${onAccessRunner}";
      # clamd may still be loading its DB on first boot — keep retrying.
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  # On-demand scanner for keys you didn't write yourself, plus the audit tool.
  environment.systemPackages = [ usbScan pkgs.clamav pkgs.lynis ];

  ###########################################################################
  # 3. Removable media: flush writes immediately + refuse execution
  ###########################################################################
  # `flush`/`sync` mean a copy is on the physical key almost as soon as your
  # file manager says "done" — so an un-ejected yank loses little and the
  # scanner sees the final bytes. noexec/nosuid/nodev stop anything on a key
  # from being run with elevated rights on this box.
  environment.etc."udisks2/mount_options.conf".text = ''
    [defaults]
    vfat_defaults=uid=$UID,gid=$GID,shortname=mixed,utf8=1,showexec,flush,noexec,nosuid,nodev
    exfat_defaults=uid=$UID,gid=$GID,iocharset=utf8,errors=remount-ro,sync,noexec,nosuid,nodev
    ntfs_defaults=uid=$UID,gid=$GID,windows_names,sync,noexec,nosuid,nodev
    ntfs3_defaults=uid=$UID,gid=$GID,windows_names,sync,noexec,nosuid,nodev
  '';

  ###########################################################################
  # 4. Weekly host-side rootkit / malware / hardening audit
  ###########################################################################
  systemd.services.lynis-audit = {
    description = "lynis system audit (rootkit / malware / hardening)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lynisCheck}";
    };
  };
  systemd.timers.lynis-audit = {
    description = "Weekly lynis audit";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;              # run after boot if the machine was off
      RandomizedDelaySec = "1h";
    };
  };
}
