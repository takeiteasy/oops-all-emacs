# el-init C helper binaries
#
# Builds elinit-logd, elinit-runas, and elinit-rlimits from el-init's
# libexec/ directory. These helpers are called by el-init Elisp at runtime
# for logging, privilege dropping, and resource limit enforcement.

{ stdenv, el-init }:

stdenv.mkDerivation {
  pname = "elinit-libexec";
  version = "0.1.0";

  src = "${el-init}/libexec";

  dontConfigure = true;
  enableParallelBuilding = true;

  buildPhase = ''
    make all
  '';

  installPhase = ''
    mkdir -p $out/libexec/elinit
    install -m 755 elinit-logd   $out/libexec/elinit/
    install -m 755 elinit-runas  $out/libexec/elinit/
    install -m 755 elinit-rlimits $out/libexec/elinit/
  '';

  meta = {
    description = "el-init C helper binaries (logd, runas, rlimits)";
    homepage = "https://github.com/emacs-os/el-init";
  };
}
