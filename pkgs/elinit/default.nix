# el-init Elisp package
#
# Installs all el-init Emacs Lisp modules to share/emacs/site-lisp/elinit/
# so the PID1 Emacs can (require 'elinit) after adding this path to load-path.

{ stdenv, el-init, emacs }:

stdenv.mkDerivation {
  pname = "elinit";
  version = "0.1.0";

  src = el-init;

  nativeBuildInputs = [ emacs ];

  buildPhase = ''
    # Byte-compile for faster loading at boot
    emacs --batch \
      --eval "(add-to-list 'load-path \".\")" \
      --eval "(batch-byte-compile)" \
      elinit.el elinit-core.el elinit-pid1.el elinit-units.el \
      elinit-log.el elinit-timer.el elinit-libexec.el \
      elinit-overrides.el elinit-sandbox.el \
      elinit-dashboard.el elinit-cli.el \
      2>&1 || true  # byte-compile warnings are non-fatal
  '';

  installPhase = ''
    dest=$out/share/emacs/site-lisp/elinit
    mkdir -p "$dest"
    cp elinit*.el "$dest/"
    # Install compiled files if present
    cp elinit*.elc "$dest/" 2>/dev/null || true

    # Install elinitctl CLI tool
    mkdir -p $out/bin
    cp sbin/elinitctl $out/bin/elinitctl
    chmod +x $out/bin/elinitctl
  '';

  meta = {
    description = "el-init: Emacs Lisp service supervisor (PID 1 support)";
    homepage = "https://github.com/emacs-os/el-init";
  };
}
