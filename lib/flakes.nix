dirname: inputs@{ self, nixpkgs, ...}: let
    inherit (nixpkgs) lib;
    inherit (import "${dirname}/vars.nix"    dirname inputs) namesToAttrs mergeAttrsUnique flipNames;
    inherit (import "${dirname}/imports.nix" dirname inputs) importWrapped importModules importOverlays importPkgsDefs importPatches packagesFromOverlay;
    #inherit (import "${dirname}/misc.nix" dirname inputs) trace;
in rec {

    # Simplified implementation of »flake-utils.lib.eachSystem«.
    forEachSystem = systems: getSystemOutputs: flipNames (namesToAttrs getSystemOutputs systems);

    # Sooner or later this should be implemented in nix itself, for now require »inputs.nixpkgs« and a system that can run »x86_64-linux« (native or through qemu).
    patchFlakeInputs = inputs: patches: outputs: let
        inherit ((import inputs.nixpkgs { overlays = [ ]; config = { }; system = builtins.currentSystem or "x86_64-linux"; }).pkgs) applyPatches fetchpatch nix;
    in outputs (builtins.mapAttrs (name: input: if name != "self" && patches?${name} && patches.${name} != [ ] then (let
        patched = (applyPatches {
            name = "${name}-patched"; src = "${input.sourceInfo or input}";
            patches = map (patch: if patch ? url then fetchpatch patch else patch) patches.${name};
        }).overrideAttrs (old: {
            outputs = [ "out" "narHash" ];
            installPhase = old.installPhase + "\n" + ''
                ${lib.getExe nix} --extra-experimental-features nix-command --offline hash path ./ >$narHash
            '';
        });
        sourceInfo = (builtins.removeAttrs (input.sourceInfo or input) [ "narHash" ]) // { inherit (patched) outPath; narHash = lib.fileContents patched.narHash; }; # (keeps (short)rev, which is not really correct, but nixpkgs' rev is used in NixOS generation names)
        dir = if input?sourceInfo.outPath && lib.hasPrefix input.sourceInfo.outPath input.outPath then lib.removePrefix input.sourceInfo.outPath input.outPath else ""; # this should work starting with nix version 2.14 (before, they are the same path)
    in (
        # sourceInfo = { lastModified; lastModifiedDate; narHash; outPath; rev?; shortRev?; }
        # A non-flake has only the attrs of »sourceInfo«.
        # A flake has »{ _type = "flake"; inputs; outputs; sourceInfo; } // outputs // sourceInfo«, where »inputs« is what's passed to the outputs function without »self«, and »outputs« is the result of calling the outputs function. Don't know the merge priority.
        # Since nix v2.14, the direct »outPath« has the relative location of the »dir« containing the »flake.nix« as suffix (if not "").
        if (!input?sourceInfo) then sourceInfo else (let
            outputs = (import "${patched.outPath}${dir}/flake.nix").outputs ({ inherit self; } // input.inputs);
            self = outputs // sourceInfo // { _type = "flake"; outPath = "${patched.outPath}${dir}"; inherit (input) inputs; inherit outputs; inherit sourceInfo; };
        in self)
    )) else input) inputs);

    # Generates implicit flake outputs by importing conventional paths in the local repo. Usage:
    #     outputs = inputs@{ self, nixpkgs, functions, ... }: functions.lib.importRepo inputs ./. (repo@{ overlays, lib, ... }: let ... in [ repo ... ]);
    # If the `flake.nix` is in a sub dir (e.g., `nix`) of a repo and some of the (implicitly) imported files need to reference something outside that sub dir, then the path needs to passed like this: `"${../.}/nix"` (i.e, a native nix path out to the root of the repo (/what needs to be referenced) and then a string path back do the flake dir).
    importRepo = inputs: flakePath: outputs: let
        repo = (lib.makeOverridable getRepo) rec {
            inherit inputs;
            path = let # Referring to the current flake directory as »./.« is quite intuitive (and »inputs.self.outPath« causes infinite recursion), but without this it adds another hash to the path (when cast to a string, because it copies it).
                pathSuffix = lib.removePrefix "${builtins.storeDir}/" flakePath;
                componentName = builtins.head (builtins.split "/" pathSuffix);
                flakeDir = lib.removePrefix componentName pathSuffix;
            in "${builtins.path { path = "${builtins.storeDir}/${componentName}"; name = "source"; }}${flakeDir}";
            dirs = builtins.mapAttrs (__: _:_ == "directory") (builtins.readDir path);
        };
        getRepo = {
            inputs, path, dirs,
            overlaysFromPkgs ? true, overlaysFromPatches ? true, applyToPackages ? pkgs: packages: packages,
        }: let
            hasDir = dir: dirs.${dir} or false == true;

            lib' = importWrapped inputs "${path}/lib";
            # (don't shadow "lib")

            overlays = let
                overlays' = importWrapped inputs "${path}/overlays";
                overlays = if overlays'.exists then overlays'.result else if hasDir "overlays" then importOverlays inputs "${path}/overlays" { } else { };
                pkgsDefs' = importWrapped inputs "${path}/pkgs";
                pkgsDefs = if pkgsDefs'.exists then pkgsDefs'.result else if hasDir "pkgs" then importPkgsDefs inputs "${path}/pkgs" { merge = "splice"; } else { };
                fromPkgs = builtins.mapAttrs (name: def: (final: prev: {
                    ${name} = final.callPackage def { };
                })) pkgsDefs;
                fromPatches = builtins.mapAttrs (names: patches: (final: prev: let
                    rename = match != null; match = builtins.match "(.+)[+](.+)" names;
                    prevName = if !rename then names else builtins.head match; aftName = if !rename then names else "${builtins.head match}-${builtins.elemAt match 1}";
                in {
                    ${aftName} = if prev?${prevName}.overrideAttrs then prev.${prevName}.overrideAttrs (old: (lib.optionalAttrs rename { pname = aftName; }) // { patches = (old.patches or [ ]) ++ builtins.attrValues patches; }) else null;
                })) (lib.filterAttrs (_: it: builtins.isAttrs it && !(lib.isDerivation it)) patches); # //patches/*/ -> attrs
                merged = (lib.optionalAttrs overlaysFromPatches fromPatches) // (lib.optionalAttrs overlaysFromPkgs fromPkgs) // overlays;
            in (lib.optionalAttrs (merged != { }) { default = lib.composeManyExtensions (builtins.attrValues merged); }) // merged;

            packages' = packagesFromOverlay { inherit inputs; apply = applyToPackages; };
            packages = lib.filterAttrs (__: _:_ != { }) (builtins.mapAttrs (_: lib.filterAttrs (_: lib.isDerivation)) packages');
            legacyPackages = lib.filterAttrs (__: _:_ != { }) (builtins.mapAttrs (_: lib.filterAttrs (_: pkg: !(lib.isDerivation pkg))) packages');

            modules' = importWrapped inputs "${path}/modules";
            modules = if modules'.exists then modules'.result else if hasDir "modules" then importModules inputs "${path}/modules" { } else { };
            nixosModules = (lib.optionalAttrs (modules != { }) { default = { imports = builtins.attrValues modules; _file = "${path}/modules#merged"; }; }) // modules;

            patches' = importWrapped inputs "${path}/patches";
            patches = if patches'.exists then patches'.result else if hasDir "patches" then importPatches inputs "${path}/patches" { } else { };

            # Nix 2.14 starts setting this correctly for all actual inputs, but not for inputs.self
            outPath = let check = path: assert path != "/"; if builtins.pathExists "${path}/flake.nix" then path else check (builtins.dirOf path); in check path;

        in (
            (if lib'.exists then { lib = lib'.result; } else { })
            // (/* if overlays == { } then { } else */ { inherit overlays; })
            // (/* if packages == { } then { } else */ { inherit packages; })
            // (/* if legacyPackages == { } then { } else */ { inherit legacyPackages; })
            // (/* if nixosModules == { } then { } else */ { inherit nixosModules; }) # TODO: only modules with no _class or _class == "nixos" should be exported as »nixosModules«. Others should become »${_class}Modules«.
            // (/* if patches == { } then { } else */ { inherit patches; })
            // { inherit outPath; }
        );

        result = outputs repo;
    in if (builtins.isList result) then mergeFlakeOutputs result else result;

    ## Composes a single (nixpkgs) overlay that applies a list of overlays, low indices first.
    mergeOverlays = overlays: (
        final: prev: lib.foldl (acc: overlay: acc // (overlay final (prev // acc))) { } overlays
    );
    # lib.composeManyExtensions

    # Combines »patchFlakeInputs« and »importRepo« in a single call. E.g.:
    # outputs = inputs: let patches = {
    #     nixpkgs = [
    #         # remote: { url = "https://github.com/NixOS/nixpkgs/pull/###.diff"; sha256 = inputs.nixpkgs.lib.fakeSha256; }
    #         # local: ./overlays/patches/nixpkgs-###.patch # (use long native path to having the path change if any of the other files in ./. change)
    #     ]; # ...
    # }; in inputs.functions.lib.patchFlakeInputsAndImportRepo inputs patches ./. (inputs@{ self, nixpkgs, ... }: repo@{ nixosModules, overlays, lib, ... }: let ... in [ repo ... ])
    patchFlakeInputsAndImportRepo = inputs: patches: flakePath: outputs: (
        patchFlakeInputs inputs patches (inputs: importRepo inputs flakePath (repo: outputs (inputs // {
            self = inputs.self // { outPath = repo.outPath; }; # (This may or may not automatically get there.)
        }) repo))
    );

    # Merges a list of flake output attribute sets.
    mergeFlakeOutputs = outputList: builtins.zipAttrsWith (type: values: (
        if ((builtins.length values) == 1) then (builtins.head values)
        else if (builtins.all builtins.isAttrs values) then (builtins.zipAttrsWith (system: values: (
            if ((builtins.length values) == 1) then (builtins.head values)
            else if (builtins.all builtins.isAttrs values) then (mergeAttrsUnique values)
            else throw "outputs.${type}.${system} has multiple values, but not all attribute sets. Can't merge."
        )) values)
        else throw "outputs.${type} has multiple values, but not all attribute sets. Can't merge."
    )) (map ( # It is quite reasonable that things meant for export are made »lib.makeOverridable«, but that does not mean that the »override« (of only one of output's components) should be exported.
        outputs: builtins.removeAttrs outputs [ "override" "overrideDerivation" ]
    ) outputList);

}
