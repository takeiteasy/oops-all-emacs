# Static Emacs 30.2 with PID1 patches
#
# Adapted from el-init's static-builds/emacs-static-nox-elinit-patched-for-pid1.nix
# Patches and source are pulled from the el-init flake input.
#
# Builds a fully statically linked Emacs binary suitable for use as Linux PID 1.
# All six library dependencies are compiled from source as static archives.
# The binary does NOT auto-activate PID1 mode; pass --pid1 explicitly.

{ lib, stdenv, fetchurl, el-init, m4, autoconf, automake, texinfo, pkg-config
, glibc, zlib }:

let
  # ── PID1 patches (from el-init source) ──────────────────────────────────
  pid1Patches = [
    "${el-init}/static-builds/patches/emacs-0001-add-pid1-runtime-mode.patch"
    "${el-init}/static-builds/patches/emacs-0002-pid1-hooks-and-signals.patch"
    "${el-init}/static-builds/patches/emacs-0003-fix-pid1-signal-handler-overrides.patch"
  ];

  # ── Static ncurses (wide-char) ───────────────────────────────────────────
  staticNcurses = stdenv.mkDerivation {
    pname = "static-ncurses";
    version = "6.5";
    src = fetchurl {
      url = "https://ftp.gnu.org/pub/gnu/ncurses/ncurses-6.5.tar.gz";
      sha256 = "1ihwjxkwgsqcm6jybqscc27l4mxbfsy81sgrwn2mg6ls4sy92v8k";
    };
    configureFlags = [
      "--with-normal" "--without-shared" "--without-debug"
      "--without-cxx" "--without-cxx-binding" "--enable-widec"
      "--without-ada" "--without-manpages" "--without-tests"
    ];
    enableParallelBuilding = true;
    postInstall = ''
      cd $out/lib
      ln -sf libncursesw.a libncurses.a
      ln -sf libncursesw.a libtinfo.a
      ln -sf libncursesw.a libtinfow.a
    '';
  };

  # ── Static GMP ───────────────────────────────────────────────────────────
  staticGmp = stdenv.mkDerivation {
    pname = "static-gmp";
    version = "6.3.0";
    src = fetchurl {
      url = "https://ftp.gnu.org/pub/gnu/gmp/gmp-6.3.0.tar.xz";
      sha256 = "1648ad1mr7c1r8lkkqshrv1jfjgfdb30plsadxhni7mq041bihm3";
    };
    nativeBuildInputs = [ m4 ];
    configureFlags = [ "--enable-static" "--disable-shared" ];
    preConfigure = ''
      export CC="gcc -std=gnu17"
    '';
    enableParallelBuilding = true;
    postInstall = ''
      rm -f $out/include/config.h
    '';
  };

  # ── Static nettle ────────────────────────────────────────────────────────
  staticNettle = stdenv.mkDerivation {
    pname = "static-nettle";
    version = "3.10.1";
    src = fetchurl {
      url = "https://ftp.gnu.org/pub/gnu/nettle/nettle-3.10.1.tar.gz";
      sha256 = "0cli5lkr7h9vxrz3j9kylnsdbw2ag6x8bpgivj06xsndq1zxvz5h";
    };
    nativeBuildInputs = [ m4 ];
    buildInputs = [ staticGmp ];
    configureFlags = [
      "--enable-static" "--disable-shared"
      "--disable-documentation" "--disable-openssl"
    ];
    preConfigure = ''
      export CFLAGS="-O2"
      export LDFLAGS="-L${staticGmp}/lib"
      export CPPFLAGS="-I${staticGmp}/include"
    '';
    enableParallelBuilding = true;
  };

  # ── Static GnuTLS ────────────────────────────────────────────────────────
  staticGnutls = stdenv.mkDerivation {
    pname = "static-gnutls";
    version = "3.8.9";
    src = fetchurl {
      url = "https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-3.8.9.tar.xz";
      sha256 = "1v9090cbajf02cw01idfbp0cgmgjn5091ff1b96hqryi0bc17qb9";
    };
    buildInputs = [ staticGmp staticNettle ];
    nativeBuildInputs = [ pkg-config ];
    configureFlags = [
      "--enable-static" "--disable-shared"
      "--disable-cxx" "--disable-tools" "--disable-doc"
      "--disable-libdane" "--disable-guile" "--disable-nls"
      "--without-p11-kit" "--without-idn" "--without-brotli" "--without-zstd"
      "--without-tpm" "--with-tpm2=no"
      "--with-included-unistring" "--with-included-libtasn1"
      "--disable-hardware-acceleration"
    ];
    preConfigure = ''
      export CFLAGS="-O2"
      export LDFLAGS="-L${staticGmp}/lib -L${staticNettle}/lib"
      export CPPFLAGS="-I${staticGmp}/include -I${staticNettle}/include"
      export GMP_LIBS="-L${staticGmp}/lib -lgmp"
      export GMP_CFLAGS="-I${staticGmp}/include"
      export NETTLE_LIBS="-L${staticNettle}/lib -lhogweed -lnettle -L${staticGmp}/lib -lgmp"
      export NETTLE_CFLAGS="-I${staticNettle}/include"
      export HOGWEED_LIBS="-L${staticNettle}/lib -lhogweed -lnettle -L${staticGmp}/lib -lgmp"
      export HOGWEED_CFLAGS="-I${staticNettle}/include"
    '';
    enableParallelBuilding = true;
  };

  # ── Static libxml2 ───────────────────────────────────────────────────────
  staticLibxml2 = stdenv.mkDerivation {
    pname = "static-libxml2";
    version = "2.15.1";
    src = fetchurl {
      url = "https://download.gnome.org/sources/libxml2/2.15/libxml2-2.15.1.tar.xz";
      sha256 = "0k65kg1j8qmjsgpx5y0gv201sn7shgr732kvgylb9iymiz0bl260";
    };
    configureFlags = [
      "--enable-static" "--disable-shared"
      "--without-python" "--without-icu" "--without-lzma"
      "--without-readline" "--without-http"
    ];
    preConfigure = ''
      export CFLAGS="-O2"
    '';
    enableParallelBuilding = true;
  };

  # ── Static tree-sitter ───────────────────────────────────────────────────
  staticTreeSitter = stdenv.mkDerivation {
    pname = "static-tree-sitter";
    version = "0.25.6";
    src = fetchurl {
      url = "https://github.com/tree-sitter/tree-sitter/archive/refs/tags/v0.25.6.tar.gz";
      sha256 = "0z4m54v3yhxgcj92k5v4gdn1yri2zb9mqv947rayhjfqqqcxjvmc";
    };
    dontConfigure = true;
    enableParallelBuilding = true;
    makeFlags = [ "PREFIX=$(out)" ];
    installFlags = [ "PREFIX=$(out)" ];
  };

in stdenv.mkDerivation {
  pname = "emacs-pid1";
  version = "30.2";

  src = fetchurl {
    url = "https://ftp.gnu.org/gnu/emacs/emacs-30.2.tar.xz";
    sha256 = "1nggbgnns7lvxn68gzlcsgwh3bigvrbn45kh6dqia9yxlqc6zwxk";
  };

  nativeBuildInputs = [ autoconf automake texinfo pkg-config ];
  buildInputs = [
    staticNcurses staticGmp staticNettle staticGnutls
    staticLibxml2 staticTreeSitter
    glibc.static zlib zlib.static
  ];

  hardeningDisable = [ "all" ];
  dontFixup = true;

  patches = pid1Patches;

  configurePhase = ''
    runHook preConfigure

    PKG_CONFIG=false ./configure \
      --prefix=$out \
      --without-all \
      --without-x \
      --without-sound \
      --without-dbus \
      --without-libsystemd \
      --without-compress-install \
      --without-native-compilation \
      --without-selinux \
      --without-gpm \
      --without-lcms2 \
      --with-modules \
      --with-threads \
      --with-zlib \
      --with-xml2=yes \
      --with-gnutls=yes \
      --with-tree-sitter=yes \
      --with-pdumper=yes \
      --with-dumping=pdumper \
      --with-file-notification=inotify \
      CFLAGS="-O2 -std=gnu17 -I${staticGmp}/include -I${staticNcurses}/include -I${staticNcurses}/include/ncursesw -I${staticNettle}/include -I${staticGnutls}/include -I${staticLibxml2}/include -I${staticTreeSitter}/include" \
      LDFLAGS="-static -no-pie -L${staticGmp}/lib -L${staticNcurses}/lib -L${staticNettle}/lib -L${staticGnutls}/lib -L${staticLibxml2}/lib -L${staticTreeSitter}/lib -Wl,--allow-multiple-definition" \
      CPPFLAGS="-I${staticGmp}/include -I${staticNcurses}/include -I${staticNcurses}/include/ncursesw -I${staticNettle}/include -I${staticGnutls}/include -I${staticLibxml2}/include -I${staticTreeSitter}/include" \
      LIBXML2_CFLAGS="-I${staticLibxml2}/include/libxml2" \
      LIBXML2_LIBS="-L${staticLibxml2}/lib -lxml2 -lz -lm" \
      LIBGNUTLS_CFLAGS="-I${staticGnutls}/include" \
      LIBGNUTLS_LIBS="-L${staticGnutls}/lib -lgnutls -L${staticNettle}/lib -lhogweed -lnettle -L${staticGmp}/lib -lgmp" \
      TREE_SITTER_CFLAGS="-I${staticTreeSitter}/include" \
      TREE_SITTER_LIBS="-L${staticTreeSitter}/lib -ltree-sitter"

    runHook postConfigure
  '';

  enableParallelBuilding = true;

  installPhase = ''
    runHook preInstall

    make DESTDIR="" install

    # ── Static linkage verification ──────────────────────────────────────
    local binary=$out/bin/emacs-30.2
    echo "=== Static linkage verification ==="

    file "$binary"
    file "$binary" | grep -q "statically linked" || { echo "FAIL: not statically linked"; exit 1; }
    echo "PASS: file reports statically linked"

    ldd_output=$(ldd "$binary" 2>&1 || true)
    echo "ldd: $ldd_output"
    echo "$ldd_output" | grep -q "not a dynamic executable" || { echo "FAIL: ldd check failed"; exit 1; }
    echo "PASS: ldd confirms not a dynamic executable"

    if readelf -d "$binary" 2>/dev/null | grep -q NEEDED; then
      echo "FAIL: has NEEDED entries"; exit 1
    fi
    echo "PASS: no NEEDED entries"

    if readelf -l "$binary" 2>/dev/null | grep -q INTERP; then
      echo "FAIL: has INTERP segment"; exit 1
    fi
    echo "PASS: no INTERP segment"

    # ── Feature verification ─────────────────────────────────────────────
    $out/bin/emacs --version
    echo "PASS: emacs --version works"
    features=$($out/bin/emacs --batch --eval '(message "%s" system-configuration-features)' 2>&1)
    echo "Features: $features"
    echo "$features" | grep -q "GNUTLS"     || { echo "FAIL: GnuTLS not enabled"; exit 1; }
    echo "$features" | grep -q "TREE_SITTER" || { echo "FAIL: tree-sitter not enabled"; exit 1; }
    echo "$features" | grep -q "MODULES"    || { echo "FAIL: modules not enabled"; exit 1; }
    echo "$features" | grep -q "LIBXML2"    || { echo "FAIL: libxml2 not enabled"; exit 1; }
    echo "PASS: all expected features present"

    # ── PID1 patch verification ──────────────────────────────────────────
    $out/bin/emacs --batch --eval '(unless (eq pid1-mode nil) (kill-emacs 1))' 2>&1
    echo "PASS: pid1-mode is nil without --pid1"
    $out/bin/emacs --pid1 --batch --eval '(unless (eq pid1-mode t) (kill-emacs 1))' 2>&1
    echo "PASS: pid1-mode is t with --pid1"
    # Note: --pid1 may not appear in --help (depends on patch version)
    # but the flag itself works (verified above via pid1-mode check)
    $out/bin/emacs --pid1 --batch --eval \
      '(unless (and (boundp (quote pid1-boot-hook))
                    (boundp (quote pid1-poweroff-hook))
                    (boundp (quote pid1-reboot-hook)))
         (kill-emacs 1))' 2>&1
    echo "PASS: PID1 hooks are defined"

    # ── Neutral startup verification ─────────────────────────────────────
    echo "=== Neutral startup verification ==="
    $out/bin/emacs --pid1 --batch \
      --eval '(when (featurep (quote elinit)) (kill-emacs 1))' 2>&1
    echo "PASS: elinit is not loaded implicitly with --pid1"
    if [ -f "$out/share/emacs/site-lisp/site-start.el" ]; then
      echo "FAIL: site-start.el found in package"; exit 1
    fi
    echo "PASS: no site-start.el in package"

    echo "=== All checks passed ==="

    runHook postInstall
  '';

  meta = with lib; {
    description = "GNU Emacs 30.2 — static, nox, PID1-patched";
    homepage = "https://www.gnu.org/software/emacs/";
    license = licenses.gpl3Plus;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "emacs";
  };
}
