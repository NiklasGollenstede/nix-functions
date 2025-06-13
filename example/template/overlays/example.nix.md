/*

# TODO: title

TODO: documentation

## Implementation

```nix
#*/# end of MarkDown, beginning of NixPkgs overlay:
dirname: inputs: final: prev: let
    inherit (final) pkgs; lib = inputs.self.lib.__internal__;
in {
/*
    # e.g.: add a patched version of a package (use the same name to replace)
    systemd-patched = prev.systemd.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
            ../patches/systemd-....patch
        ];
    });

    # e.g.: add a prebuilt program as package
    qemu-aarch64-static = pkgs.stdenv.mkDerivation {
        name = "qemu-aarch64-static";
        src = pkgs.fetchurl {
            url = "https://github.com/multiarch/qemu-user-static/releases/download/v6.1.0-8/qemu-aarch64-static";
            sha256 = "075l122p3qfq6nm07qzvwspmsrslvrghar7i5advj945lz1fm6dd";
        }; dontUnpack = true;
        installPhase = "install -D -m 0755 $src $out/bin/qemu-aarch64-static";
    };

    # e.g.: update (or pin the version of) a package
    raspberrypifw = prev.raspberrypifw.overrideAttrs (old: rec {
        version = "1.20220308";
        src = pkgs.fetchFromGitHub {
            owner = "raspberrypi"; repo = "firmware"; rev = version;
            sha256 = "sha256-pwhI9sklAGq5+fJqQSadrmW09Wl6+hOFI/hEewkkLQs=";
        };
    });

    # e.g.: add a program as new package
    udptunnel = pkgs.stdenv.mkDerivation rec {
        pname = "udptunnel"; version = "1"; # (not versioned)

        src = pkgs.fetchFromGitHub {
            owner = "rfc1036"; repo = pname; rev = "482ed94388a0dde68561584926c7d5c14f079f7e"; # 2018-11-18
            sha256 = "1wkzzxslwjm5mbpyaq30bilfi2mfgi2jqld5l15hm5076mg31vp7";
        };
        patches = [ ../patches/....patch ];

        installPhase = ''
            mkdir -p $out/bin $out/share/udptunnel
            cp -T udptunnel $out/bin/${pname}
            cp COPYING $out/share/udptunnel
        '';

        meta = {
            homepage = "https://github.com/rfc1036/udptunnel";
            description = "Tunnel UDP packets in a TCP connection ";
            license = lib.licenses.gpl2;
            maintainers = [ ];
            platforms = lib.platforms.linux;
        };
    };

    # e.g.: override a python package:
    pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [ (final: prev: {
        mox = prev.mox.overridePythonAttrs (old: {
            disabled = false; # (with the way that "disabled" is currently being evaluated, this does not apply in time)
            # (other attributes should work, though)
        });
    }) ];
 */
}
