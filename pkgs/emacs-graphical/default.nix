# Graphical Emacs with EXWM desktop environment
#
# Dynamically linked Emacs with X11 support, bundled with EXWM, XELB, and vterm.
# This is a child process of emacs-pid1 — no PID1 patches needed.

{ pkgs }:

(pkgs.emacsPackagesFor pkgs.emacs30).emacsWithPackages (epkgs: [
  epkgs.exwm
  epkgs.xelb
  epkgs.vterm
])
