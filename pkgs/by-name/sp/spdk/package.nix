{
  lib,
  stdenv,
  fetchFromGitHub,
  ncurses,
  python3,
  cunit,
  dpdk,
  fuse3,
  libaio,
  libbsd,
  libuuid,
  nasm,
  autoconf,
  automake,
  libtool,
  numactl,
  openssl,
  pkg-config,
  zlib,
  zstd,
  libpcap,
  libnl,
  elfutils,
  fetchurl,
  jansson,
  ensureNewerSourcesForZipFilesHook,
  runtimeShell,
}:

stdenv.mkDerivation rec {
  pname = "spdk";

  version = "26.09";

  src = fetchFromGitHub {
    owner = "spdk";
    repo = "spdk";
    tag = "v${version}";
    hash = "sha256-9LaQwzNmujWlBTMS422VpqheQWfSUuCvW7h450i9FIQ=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    python3
    python3.pkgs.pip
    python3.pkgs.hatchling
    python3.pkgs.wheel
    python3.pkgs.wrapPython
    # Used by scripts/genrpc.py to generate the RPC headers
    python3.pkgs.pyyaml
    python3.pkgs.jinja2
    python3.pkgs.tabulate
    pkg-config
    ensureNewerSourcesForZipFilesHook
  ];

  buildInputs = [
    cunit
    dpdk
    fuse3
    jansson
    libaio
    libbsd
    elfutils
    libuuid
    libpcap
    libnl
    numactl
    openssl
    ncurses
    zlib
    zstd
    nasm
    autoconf
    automake
    libtool
  ];

  propagatedBuildInputs = [
    python3.pkgs.configshell-fb
  ];

  patches = [
    ./patches/revert-patchelf.patch
  ];

  postPatch = ''
    patchShebangs .
    # Override uv pip install command to use hatchling directly without downloading dependencies
    substituteInPlace python/Makefile \
      --replace-fail "uv pip install \$(USE_SYSTEM_PYTHON) --prefix=\$(DESTDIR)\$(CONFIG_PREFIX)" \
                     "python3 -m pip install --no-deps --no-build-isolation --prefix=\$(DESTDIR)\$(CONFIG_PREFIX)"
  '';

  enableParallelBuilding = true;

  # The vendored isa-l only detects and checks nasm itself when AS is empty
  preConfigure = ''
    unset AS
  '';

  configureFlags = [
    "--with-dpdk=${dpdk}"
    "--with-crypto"
  ]
  ++ lib.optional (!stdenv.hostPlatform.isStatic) "--with-shared";

  # spdk does shenanigans with patchelf, so we need to stop them from messing with rpath
  preInstall = ''
    patchelf() { true; }
    export -f patchelf
  '';

  postInstall = ''
    unset patchelf

    # Clean up rpaths to remove /build references to the vendored isa-l and isa-l_crypto libs
    for f in $(find $out/lib $out/bin -executable -type f 2>/dev/null); do
      if patchelf --print-rpath "$f" 2>/dev/null | grep /build; then
        echo "Stripping rpath of $f"
        newrp=$(patchelf --print-rpath "$f" | sed -r "s|/build[^:]*:||g")
        patchelf --set-rpath "$newrp" "$f"
      fi
    done

    # SPDK scripts assume that they can read the includes also relative to the scripts.
    # Therefore we are not copying them into $out/share.
    mkdir $out/scripts
    cp  ./scripts/common.sh ./scripts/setup.sh $out/scripts
    cat > $out/bin/spdk-setup << EOF
    #!${runtimeShell}
    exec $out/scripts/setup.sh "\$@"
    EOF
    chmod +x  $out/bin/spdk-setup
  '';

  postCheck = ''
    python3 -m spdk
  '';

  postFixup = ''
    wrapPythonPrograms
    ${lib.optionalString (!stdenv.hostPlatform.isStatic) ''
      # .pc files are not working properly with static linking and might just confuse other build systems
      rm $out/lib/*.a
    ''}
  '';

  env.NIX_CFLAGS_COMPILE = "-mssse3"; # Necessary to compile.

  meta = {
    description = "Set of libraries for fast user-mode storage";
    homepage = "https://spdk.io/";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" ];
    maintainers = with lib.maintainers; [ ths-on ];
  };
}
