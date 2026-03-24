# el-init as PID 1 with core services, EXWM graphical desktop, and session management
#
# Overrides boot.systemdExecutable so that NixOS's stage-2 init script
# execs into emacs-pid1 instead of systemd. All NixOS activation
# infrastructure (user creation, /etc, /bin/sh) runs first.
#
# Services: D-Bus, NetworkManager, PipeWire, WirePlumber, Xorg, EXWM, acpid.

{ config, pkgs, lib, emacs-pid1, elinit, elinit-libexec, emacs-graphical, ... }:

let
  util-linux = pkgs.util-linux;

  # ── EXWM init.el for the graphical Emacs session ──────────────────────
  exwmInitEl = pkgs.writeText "exwm-init.el" ''
    ;;; exwm-init.el --- EXWM desktop session for emacs-os -*- lexical-binding: t -*-

    ;; ── EXWM core ──────────────────────────────────────────────────────
    (require 'exwm)
    (require 'exwm-randr)

    ;; Number of workspaces
    (setq exwm-workspace-number 4)

    ;; ── Window naming ──────────────────────────────────────────────────
    (add-hook 'exwm-update-class-hook
              (lambda () (exwm-workspace-rename-buffer exwm-class-name)))
    (add-hook 'exwm-update-title-hook
              (lambda ()
                (when (or (not exwm-class-name) (string= exwm-class-name ""))
                  (exwm-workspace-rename-buffer exwm-title))))

    ;; ── Global keybindings ─────────────────────────────────────────────
    (setq exwm-input-global-keys
          `(([?\s-r] . exwm-reset)
            ([?\s-w] . exwm-workspace-switch)
            ([?\s-&] . (lambda (command)
                         (interactive (list (read-shell-command "$ ")))
                         (start-process-shell-command command nil command)))
            ([s-return] . (lambda () (interactive)
                            (if (fboundp 'vterm)
                                (vterm)
                              (term "/bin/sh"))))
            ([?\s-d] . emacs-os-elinit-dashboard)
            ([?\s-l] . emacs-os-lock-screen)
            ([XF86PowerOff] . emacs-os-lock-screen)
            ,@(mapcar (lambda (i)
                        `(,(kbd (format "s-%d" i)) .
                          (lambda () (interactive)
                            (exwm-workspace-switch-create ,i))))
                      (number-sequence 0 9))))

    ;; ── Simulation keys (line-mode) ────────────────────────────────────
    (setq exwm-input-simulation-keys
          '(([?\C-b] . [left])
            ([?\C-f] . [right])
            ([?\C-p] . [up])
            ([?\C-n] . [down])
            ([?\C-a] . [home])
            ([?\C-e] . [end])
            ([?\M-v] . [prior])
            ([?\C-v] . [next])
            ([?\C-d] . [delete])
            ([?\C-k] . [S-end delete])))

    ;; ── Mode-line status ───────────────────────────────────────────────
    (display-time-mode 1)
    (setq display-time-24hr-format t)
    (setq display-time-default-load-average nil)

    ;; ── System PATH and environment for shell commands ─────────────────
    (add-to-list 'exec-path "/run/current-system/sw/bin")
    (setenv "PATH" (concat "/run/current-system/sw/bin:" (getenv "PATH")))
    (setenv "EMACS_SOCKET_NAME" "/run/elinit/elinit")

    ;; ── el-init dashboard ──────────────────────────────────────────────
    (defun emacs-os-elinit-dashboard ()
      "Show el-init service status."
      (interactive)
      (let ((buf (get-buffer-create "*el-init status*")))
        (with-current-buffer buf
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert (shell-command-to-string "elinitctl status"))
            (goto-char (point-min)))
          (special-mode))
        (switch-to-buffer buf)))

    ;; ── Screen lock and power management ────────────────────────────────
    (defun emacs-os-lock-screen ()
      "Lock the X11 screen using slock."
      (interactive)
      (start-process "slock" nil "/run/wrappers/bin/slock"))

    (defun emacs-os-request-suspend ()
      "Ask PID1 el-init to suspend the system."
      (interactive)
      (call-process "emacsclient" nil nil nil
                    "-s" "/run/elinit/elinit"
                    "--eval" "(emacs-os-suspend)"))

    ;; ── vterm ──────────────────────────────────────────────────────────
    (require 'vterm nil t)

    ;; ── System tray (optional) ───────────────────────────────────────
    (ignore-errors
      (require 'exwm-systemtray nil t)
      (when (fboundp 'exwm-systemtray-enable)
        (exwm-systemtray-enable)))

    ;; ── Enable EXWM (must be last) ────────────────────────────────────
    (exwm-enable)
  '';

  # ── PID 1 Elisp init ──────────────────────────────────────────────────
  elinitInitEl = pkgs.writeText "elinit-init.el" ''
    ;;; elinit-init.el --- PID 1 boot configuration for emacs-os -*- lexical-binding: t -*-

    ;; Configure elinit for NixOS paths
    (setq elinit-log-directory "/var/log/elinit")
    (setq elinit-overrides-file "/var/lib/elinit/overrides.eld")
    (setq elinit-timer-state-file "/var/lib/elinit/timer-state.eld")
    (setq elinit-unit-authority-path '("/var/lib/elinit/units/" "/etc/elinit.el/"))
    (setq elinit-libexec-build-on-startup 'never)
    (setq elinit-default-target-link "graphical.target")

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

    ;; ── Power management (Milestone 1.6) ────────────────────────────────
    (defvar emacs-os-pre-suspend-hook nil
      "Hook run before system suspend.")

    (defvar emacs-os-post-resume-hook nil
      "Hook run after system resume.")

    (defvar emacs-os-suspend-enabled nil
      "When non-nil, `emacs-os-suspend' writes to /sys/power/state.
Disabled by default because QEMU virt cannot wake from suspend.
Set to t on real hardware where wake events (keyboard, power button) work.")

    (defun emacs-os-suspend ()
      "Lock screen and optionally suspend the system.
Always locks via slock.  When `emacs-os-suspend-enabled' is non-nil,
also writes freeze to /sys/power/state in a background subprocess.
Runs `emacs-os-pre-suspend-hook' before and `emacs-os-post-resume-hook'
after resume."
      (interactive)
      (run-hooks 'emacs-os-pre-suspend-hook)
      ;; Lock screen
      (start-process "slock" nil "/run/wrappers/bin/slock")
      (if emacs-os-suspend-enabled
          ;; Real hardware: suspend in background subprocess
          (let ((proc (start-process "suspend" nil "/bin/sh" "-c"
                        "sleep 1; echo freeze > /sys/power/state")))
            (set-process-sentinel proc
              (lambda (_p _e) (run-hooks 'emacs-os-post-resume-hook))))
        ;; QEMU / no suspend: just run post-resume hook immediately
        (message "emacs-os: suspend skipped (emacs-os-suspend-enabled is nil)")
        (run-hooks 'emacs-os-post-resume-hook)))
  '';

  # ── PID 1 wrapper script ──────────────────────────────────────────────
  emacsInit = pkgs.writeShellScript "emacs-init" ''
    mkdir -p /var/log/elinit /var/lib/elinit /var/lib/elinit/units /run/elinit
    mkdir -p /run/dbus /run/pipewire /var/lib/NetworkManager /var/lib/dbus
    mkdir -p /tmp/.X11-unix
    mkdir -p /home/emacs && chown emacs:users /home/emacs
    # Set up slock setuid wrapper (security.wrappers uses systemd, which we don't run)
    mkdir -p /run/wrappers/bin
    cp ${pkgs.slock}/bin/slock /run/wrappers/bin/slock
    chown root:root /run/wrappers/bin/slock
    chmod u+s,u+rx,g+x,o+x /run/wrappers/bin/slock
    # Create OpenGL driver symlink (normally done by systemd-tmpfiles)
    ln -sfn ${pkgs.mesa.drivers} /run/opengl-driver
    ${pkgs.inetutils}/bin/hostname emacs-os
    # Load kernel modules (no systemd-modules-load to do this)
    ${pkgs.kmod}/bin/modprobe virtio_input 2>/dev/null || true
    ${pkgs.kmod}/bin/modprobe virtio_gpu 2>/dev/null || true
    ${pkgs.kmod}/bin/modprobe drm 2>/dev/null || true
    # Generate machine-id if missing (D-Bus requires it)
    if [ ! -f /etc/machine-id ]; then
      ${pkgs.dbus}/bin/dbus-uuidgen > /etc/machine-id
    fi
    export TERM=''${TERM:-dumb}
    export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket
    export PATH="${pkgs.coreutils}/bin:${pkgs.util-linux}/bin:${elinit}/bin:$PATH"
    echo "starting emacs-pid1 (el-init)..."
    exec ${emacs-pid1}/bin/emacs --pid1 --fg-daemon=elinit -Q --load ${elinitInitEl} </dev/null 2>&1
  '';

  # ── Login script (serial console, bypasses PAM) ───────────────────────
  loginScript = pkgs.writeShellScript "elinit-login" ''
    export HOME=/root
    export USER=root
    export LOGNAME=root
    export SHELL=/bin/sh
    export TERM=linux
    export EMACS_SOCKET_NAME=/run/elinit/elinit
    export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket
    export PATH="${pkgs.coreutils}/bin:${pkgs.util-linux}/bin:${elinit}/bin:${emacs-pid1}/bin:/run/current-system/sw/bin"
    cd /root
    echo ""
    echo "emacs-os (el-init) - $(hostname)"
    echo ""
    exec ${pkgs.bashInteractive}/bin/bash -l
  '';

  # ── Xorg wrapper (uses NixOS-generated config) ────────────────────────
  xorgWrapper = pkgs.writeShellScript "xorg-wrapper" ''
    exec ${pkgs.xorg-server}/bin/Xorg :0 \
      -nolisten tcp \
      -novtswitch \
      -ac \
      -config /etc/X11/xorg.conf \
      -logfile /var/log/Xorg.0.log \
      vt7
  '';

  # ── EXWM wrapper (waits for Xorg stability) ─────────────────────────
  # Problem: udevadm trigger causes GPU device re-enumeration ~20s after
  # Xorg starts, briefly killing the display. If EXWM connects before
  # re-enumeration finishes, its X connection dies.
  # Strategy: wait at least 30s total (past the re-enumeration window)
  # AND require 5s continuous X stability before launching EXWM.
  exwmWrapper = pkgs.writeShellScript "exwm-wrapper" ''
    export DISPLAY=:0
    export PATH="/run/current-system/sw/bin:$PATH"
    STABLE=0       # consecutive seconds X has been reachable
    WAITED=0       # total seconds waited
    MIN_WAIT=30    # minimum wait to clear GPU re-enumeration window
    MAX_WAIT=90    # give up after this many seconds
    while [ $WAITED -lt $MAX_WAIT ]; do
      if ${pkgs.xdpyinfo}/bin/xdpyinfo -display :0 >/dev/null 2>&1; then
        STABLE=$((STABLE + 1))
      else
        STABLE=0
      fi
      sleep 1
      WAITED=$((WAITED + 1))
      # Only launch after min wait AND stability threshold
      if [ $WAITED -ge $MIN_WAIT ] && [ $STABLE -ge 5 ]; then
        break
      fi
    done
    if [ $STABLE -lt 5 ]; then
      echo "Xorg not stable after ''${MAX_WAIT}s, will retry" >&2
      exit 1
    fi
    echo "Xorg stable for ''${STABLE}s (waited ''${WAITED}s total), launching EXWM" >&2
    exec ${util-linux}/bin/runuser -u emacs -- \
      env HOME=/home/emacs USER=emacs DISPLAY=:0 \
      ${emacs-graphical}/bin/emacs -Q --load ${exwmInitEl}
  '';

  # ── el-init unit files ─────────────────────────────────────────────────

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

  # ── Core services (Milestone 1.4) ─────────────────────────────────────

  dbusUnit = pkgs.writeText "dbus.el" ''
    (:id "dbus"
     :description "D-Bus system message bus"
     :command "${pkgs.dbus}/bin/dbus-daemon --system --nofork --address=unix:path=/run/dbus/system_bus_socket"
     :type simple
     :enabled t
     :wanted-by ("multi-user.target")
     :restart always
     :logging t)
  '';

  networkmgrUnit = pkgs.writeText "networkmanager.el" ''
    (:id "networkmanager"
     :description "Network management daemon"
     :command "${pkgs.networkmanager}/bin/NetworkManager --no-daemon"
     :type simple
     :enabled t
     :wanted-by ("multi-user.target")
     :requires ("dbus")
     :after ("dbus")
     :restart always
     :logging t)
  '';

  pipewireUnit = pkgs.writeText "pipewire.el" ''
    (:id "pipewire"
     :description "PipeWire multimedia server"
     :command "${pkgs.pipewire}/bin/pipewire"
     :type simple
     :enabled t
     :wanted-by ("multi-user.target")
     :requires ("dbus")
     :after ("dbus")
     :environment (("XDG_RUNTIME_DIR" . "/run/pipewire"))
     :restart always
     :logging t)
  '';

  wireplumberUnit = pkgs.writeText "wireplumber.el" ''
    (:id "wireplumber"
     :description "PipeWire session manager"
     :command "${pkgs.wireplumber}/bin/wireplumber"
     :type simple
     :enabled t
     :wanted-by ("multi-user.target")
     :requires ("dbus" "pipewire")
     :after ("dbus" "pipewire")
     :environment (("XDG_RUNTIME_DIR" . "/run/pipewire"))
     :restart always
     :logging t)
  '';

  # ── Device management ───────────────────────────────────────────────

  # udev wrapper: start systemd-udevd then trigger device events
  udevWrapper = pkgs.writeShellScript "udev-wrapper" ''
    # Start udevd in background, then trigger all devices so Xorg can find inputs
    ${config.systemd.package}/lib/systemd/systemd-udevd &
    UDEV_PID=$!
    sleep 0.5
    ${config.systemd.package}/bin/udevadm trigger --action=add
    ${config.systemd.package}/bin/udevadm settle --timeout=10
    # Keep running (el-init expects the process to stay alive for :type simple)
    wait $UDEV_PID
  '';

  udevUnit = pkgs.writeText "udev.el" ''
    (:id "udev"
     :description "Device manager (udev)"
     :command "${udevWrapper}"
     :type simple
     :enabled t
     :wanted-by ("multi-user.target")
     :restart always
     :logging t)
  '';

  # ── Graphical session (Milestone 1.5) ─────────────────────────────────

  xorgUnit = pkgs.writeText "xorg.el" ''
    (:id "xorg"
     :description "X.Org display server"
     :command "${xorgWrapper}"
     :type simple
     :enabled t
     :wanted-by ("graphical.target")
     :requires ("dbus" "udev")
     :after ("dbus" "udev")
     :restart always
     :logging t)
  '';

  emacsGraphicalUnit = pkgs.writeText "emacs-graphical.el" ''
    (:id "emacs-graphical"
     :description "Emacs graphical session (EXWM desktop)"
     :command "${exwmWrapper}"
     :type simple
     :enabled t
     :wanted-by ("graphical.target")
     :requires ("xorg")
     :after ("xorg" "dbus" "pipewire")
     :environment (("DISPLAY" . ":0")
                   ("DBUS_SYSTEM_BUS_ADDRESS" . "unix:path=/run/dbus/system_bus_socket"))
     :restart always
     :restart-sec 5
     :logging t)
  '';

  # ── ACPI power management (Milestone 1.6) ─────────────────────────────

  acpiHandler = pkgs.writeShellScript "acpi-handler" ''
    case "$1" in
      button/power)
        ${emacs-pid1}/bin/emacsclient -s /run/elinit/elinit \
          --eval '(emacs-os-suspend)' || true
        ;;
    esac
  '';

  acpiEventConfig = pkgs.writeText "power" ''
event=button/power
action=${acpiHandler} %e
  '';

  acpiEventsDir = pkgs.runCommand "acpi-events" {} ''
    mkdir -p $out
    cp ${acpiEventConfig} $out/power
  '';

  # acpid: disabled on QEMU aarch64 virt (no ACPI netlink support).
  # Power button is handled via EXWM XF86PowerOff keybinding instead.
  # Re-enable on real hardware where ACPI events work.
  acpidUnit = pkgs.writeText "acpid.el" ''
    (:id "acpid"
     :description "ACPI event daemon"
     :command "${pkgs.acpid}/bin/acpid -f -c ${acpiEventsDir}"
     :type simple
     :enabled nil
     :wanted-by ("multi-user.target")
     :after ("udev")
     :restart always
     :logging t)
  '';

  unitDir = pkgs.runCommand "elinit-units" {} ''
    mkdir -p $out
    cp ${gettyUnit} $out/getty-ttyAMA0.el
    cp ${multiUserTarget} $out/multi-user.target.el
    cp ${dbusUnit} $out/dbus.el
    cp ${networkmgrUnit} $out/networkmanager.el
    cp ${pipewireUnit} $out/pipewire.el
    cp ${wireplumberUnit} $out/wireplumber.el
    cp ${udevUnit} $out/udev.el
    cp ${xorgUnit} $out/xorg.el
    cp ${emacsGraphicalUnit} $out/emacs-graphical.el
    cp ${acpidUnit} $out/acpid.el
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

  # D-Bus system bus address for all shells
  environment.variables.DBUS_SYSTEM_BUS_ADDRESS = "unix:path=/run/dbus/system_bus_socket";

  # Remove systemd NSS module from nsswitch — systemd isn't running
  system.nssDatabases = {
    passwd = lib.mkForce [ "files" ];
    group = lib.mkForce [ "files" ];
    shadow = lib.mkForce [ "files" ];
    hosts = lib.mkForce [ "files" "dns" ];
  };
}
