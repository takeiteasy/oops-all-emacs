# Milestone 1.3: Replace systemd with el-init as PID 1
#
# Overrides boot.systemdExecutable so that NixOS's stage-2 init script
# execs into emacs-pid1 instead of systemd. All NixOS activation
# infrastructure (user creation, /etc, /bin/sh) runs first.

{ config, pkgs, lib, emacs-pid1, elinit, elinit-libexec, ... }:

let
  util-linux = pkgs.util-linux;

  # The Elisp init file loaded by emacs-pid1 at startup
  elinitInitEl = pkgs.writeText "elinit-init.el" ''
    ;;; elinit-init.el --- PID 1 boot configuration for emacs-os -*- lexical-binding: t -*-

    ;; Configure elinit for NixOS paths
    (setq elinit-log-directory "/var/log/elinit")
    (setq elinit-overrides-file "/var/lib/elinit/overrides.eld")
    (setq elinit-timer-state-file "/var/lib/elinit/timer-state.eld")
    ;; Authority path: writable dir first (for timer seeding), then Nix read-only units.
    ;; Higher-index entries take precedence in resolution, so /etc/elinit.el/ wins.
    (setq elinit-unit-authority-path '("/var/lib/elinit/units/" "/etc/elinit.el/"))
    (setq elinit-libexec-build-on-startup 'never)
    (setq elinit-default-target-link "multi-user.target")

    ;; Override libexec helper paths to point to Nix store
    (setq elinit-logd-command "${elinit-libexec}/libexec/elinit/elinit-logd")
    (with-eval-after-load 'elinit-libexec
      (setq elinit-runas-command "${elinit-libexec}/libexec/elinit/elinit-runas")
      (setq elinit-rlimits-command "${elinit-libexec}/libexec/elinit/elinit-rlimits"))

    ;; Add elinit Elisp to load-path
    (add-to-list 'load-path "${elinit}/share/emacs/site-lisp/elinit")

    ;; Load elinit — triggers pid1 hook registration via elinit-pid1.el
    (require 'elinit)

    ;; Start Emacs server so elinitctl (emacsclient) can connect
    (require 'server)
    (setq server-name "elinit")
    (setq server-socket-dir "/run/elinit")
    (make-directory "/run/elinit" t)
    (set-file-modes "/run/elinit" #o700)
    (server-start)

    ;; pid1-boot-hook fires after startup → elinit--pid1-boot → elinit-start
    ;; → loads units from /etc/elinit.el/, builds DAG, starts services
  '';

  # Wrapper script that NixOS execs instead of systemd.
  # The init script calls: exec <systemdExecutable> "$@"
  # Our wrapper sets up directories then execs emacs-pid1.
  emacsInit = pkgs.writeShellScript "emacs-init" ''
    mkdir -p /var/log/elinit /var/lib/elinit /var/lib/elinit/units /run/elinit
    hostname emacs-os
    export TERM=''${TERM:-dumb}
    export PATH="${pkgs.coreutils}/bin:${pkgs.util-linux}/bin:${elinit}/bin:$PATH"
    echo "starting emacs-pid1 (el-init)..."
    # --fg-daemon keeps Emacs in foreground (no fork, safe for PID 1)
    # --pid1 enables PID 1 mode (zombie reaping, signal hooks)
    # -Q skips user init files (we load our own via --load)
    exec ${emacs-pid1}/bin/emacs --pid1 --fg-daemon=elinit -Q --load ${elinitInitEl} </dev/null 2>&1
  '';

  # Login script that bypasses PAM (systemd-logind not available)
  loginScript = pkgs.writeShellScript "elinit-login" ''
    export HOME=/root
    export USER=root
    export LOGNAME=root
    export SHELL=/bin/sh
    export TERM=linux
    export EMACS_SOCKET_NAME=/run/elinit/elinit
    export PATH="${pkgs.coreutils}/bin:${pkgs.util-linux}/bin:${elinit}/bin:${emacs-pid1}/bin:/run/current-system/sw/bin"
    cd /root
    echo ""
    echo "emacs-os (el-init) - $(hostname)"
    echo ""
    exec ${pkgs.bashInteractive}/bin/bash -l
  '';

  # el-init unit files with Nix store paths interpolated
  gettyUnit = pkgs.writeText "getty-ttyAMA0.el" ''
    (:id "getty-ttyAMA0"
     :description "Serial console login (auto-login root)"
     :command "${util-linux}/bin/agetty --autologin root --noclear --login-program ${loginScript} ttyAMA0 115200 linux"
     :type simple
     :enabled t
     :wanted-by ("multi-user.target")
     :restart always)
  '';

  multiUserTarget = pkgs.writeText "multi-user.target.el" ''
    (:id "multi-user.target"
     :type target
     :enabled t
     :description "Multi-user system")
  '';

  unitDir = pkgs.runCommand "elinit-units" {} ''
    mkdir -p $out
    cp ${gettyUnit} $out/getty-ttyAMA0.el
    cp ${multiUserTarget} $out/multi-user.target.el
  '';

in {
  # Install unit files to /etc/elinit.el/
  environment.etc."elinit.el" = {
    source = unitDir;
  };

  # Replace systemd with our emacs wrapper
  boot.systemdExecutable = toString emacsInit;

  # Set EMACS_SOCKET_NAME so elinitctl finds the server without --socket
  environment.variables.EMACS_SOCKET_NAME = "/run/elinit/elinit";

  # Remove systemd NSS module from nsswitch — systemd isn't running,
  # so the systemd NSS plugin can't resolve users, causing login failures.
  system.nssDatabases = {
    passwd = lib.mkForce [ "files" ];
    group = lib.mkForce [ "files" ];
    shadow = lib.mkForce [ "files" ];
    hosts = lib.mkForce [ "files" "dns" ];
  };
}
