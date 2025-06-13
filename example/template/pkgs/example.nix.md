/*

# TODO: title

TODO: documentation

## Implementation

```nix
#*/# end of MarkDown, beginning of NixPkgs package (callPackage argument):
dirname: inputs: {
    #gcc, overrideCC, stdenv,
    llvmPackages,
    fetchFromGitHub, nix-update-script,
    ninja, buildPackages,
    libpulseaudio,
    ncurses,
    gnustep,
lib }: let

    # Repo README says to use gcc-objc, gnustep.libobjc wants to be used with clang. clang simply works.
    #gcc-objc = (gcc.override (old: { cc = old.cc.override { langObjC = true; }; })); # doesn't like gnustep
    #stdenv = overrideCC stdenv gcc-objc;
    stdenv = llvmPackages.stdenv;

in stdenv.mkDerivation rec {
    pname = "pacmixer";
    version = "0.6.4"; # 2023-03-30 / 700c2fee5907e4dda435377f4ed1bd1227b0ccf9

    src = fetchFromGitHub { # https://github.com/KenjiTakahashi/pacmixer
        owner = "KenjiTakahashi"; repo = pname; rev = version;
        hash = "sha256-2cIrjix7uVw8+etBQooqKItCkTVVLhk2I5+aLx6jtLc=";
    };
    passthru.updateScript = nix-update-script { };

    nativeBuildInputs = [ ninja buildPackages.gnustep.wrapGNUstepAppsHook buildPackages.gnustep.make ]; # (only relevant when cross-compiling: pretty sure that when just stating gnustep.* here, Nix has no way to automatically pass the buildPackages version)
    buildInputs = [ libpulseaudio ncurses gnustep.base gnustep.libobjc ];

    postPatch = ''
        sed -i 's;gcc -MMD -MF $out.d $flags $cppflags;g++ -MMD -MF $out.d $flags $cppflags;' defs.ninja # use C++ compiler for C++ (no idea why that was different)
        sed -i 's;gcc;clang;' defs.ninja ; sed -i 's;g++;clang++;' defs.ninja # use clang instead of gcc
        sed -i 's;-lcurses;-lncurses;' defs.ninja
    '';

    buildPhase = ''
        runHook preBuild
        bash mk
        runHook postBuild
    '';
    installPhase = ''
        runHook preInstall
        PREFIX=$out bash mk install
        runHook postInstall
    '';

    meta = {
        homepage = "https://github.com/KenjiTakahashi/pacmixer";
        description = "An alsamixer alike for PulseAudio";
        mainProgram = pname;
        license = lib.licenses.gpl3;
        maintainers = [ ]; # lib.maintainers
        platforms = lib.platforms.linux;
    };
}
