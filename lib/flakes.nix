dirname: inputs@{ self, nixpkgs, ...}: let
    inherit (nixpkgs) lib;
    inherit (import "${dirname}/vars.nix"    dirname inputs) namesToAttrs mapMerge mapMergeUnique mergeAttrsUnique flipNames;
    inherit (import "${dirname}/imports.nix" dirname inputs) importWrapped;
    inherit (import "${dirname}/scripts.nix" dirname inputs) substituteImplicit extractBashFunction;
    setup-scripts = (import "${dirname}/setup-scripts" "${dirname}/setup-scripts"  inputs);
    inherit (import "${dirname}/misc.nix" dirname inputs) trace;
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
                ${lib.getExe nix} --extra-experimental-features nix-command hash path ./ >$narHash
            '';
        });
        sourceInfo = (builtins.removeAttrs (input.sourceInfo or input) [ "narHash" ]) // { inherit (patched) outPath; narHash = lib.fileContents patched.narHash; }; # (keeps (short)rev, which is not really correct, but nixpkgs' rev is used in NixOS generation names)
        dir = if input?sourceInfo.outPath && lib.hasPrefix input.outPath input.sourceInfo.outPath then lib.removePrefix input.sourceInfo.outPath input.outPath else ""; # this should work starting with nix version 2.14 (before, they are the same path)
    in (
        # sourceInfo = { lastModified; lastModifiedDate; narHash; outPath; rev?; shortRev?; }
        # A non-flake has only the attrs of »sourceInfo«.
        # A flake has »{ _type = "flake"; inputs; outputs; sourceInfo; } // outputs // sourceInfo«, where »inputs« is what's passed to the outputs function without »self«, and »outputs« is the result of calling the outputs function. Don't know the merge priority.
        # Since nix v2.14, the direct »outPath« has the relative location of the »dir« containing the »flake.nix« as suffix (if not "").
        if (!input?sourceInfo) then sourceInfo else (let
            outputs = (import "${patched.outPath}${dir}/flake.nix").outputs ({ self = sourceInfo // outputs; } // input.inputs);
        in outputs // sourceInfo // { _type = "flake"; outPath = "${patched.outPath}${dir}"; inherit (input) inputs; inherit outputs; inherit sourceInfo; })
    )) else input) inputs);

    # Generates implicit flake outputs by importing conventional paths in the local repo. E.g.:
    #     outputs = inputs@{ self, nixpkgs, functions, ... }: functions.lib.importRepo inputs ./. (repo@{ overlays, lib, ... }: let ... in [ repo ... ])
    # If the `flake.nix` is in a sub dir (e.g., `nix`) of a repo and some of the (implicitly) imported files need to reference something outside that sub dir, then the path needs to passed like this: `"${../.}/nix"` (i.e, a native nix path out to the root of the repo (/what needs to be referenced) and then a string path back do the flake dir).
    importRepo = inputs: flakePath': outputs: let
        pathSuffix = lib.removePrefix "${builtins.storeDir}/" flakePath';
        componentName = builtins.head (builtins.split "/" pathSuffix);
        flakeDir = lib.removePrefix componentName pathSuffix;
        flakePath = "${builtins.path { path = "${builtins.storeDir}/${componentName}"; name = "source"; }}${flakeDir}"; # Referring to the current flake directory as »./.« is quite intuitive (and »inputs.self.outPath« causes infinite recursion), but without this it adds another hash to the path (when cast to a string, because it copies it).
    in let result = (outputs (
        (let it                = importWrapped inputs "${flakePath}/lib";      in if it.exists then {
            lib = it.result;
        } else { }) // (let it = importWrapped inputs "${flakePath}/overlays"; in if it.exists then {
            overlays = { default = final: prev: builtins.foldl' (prev: overlay: prev // (overlay final prev)) prev (builtins.attrValues it.result); } // it.result;
        } else { }) // (let it = importWrapped inputs "${flakePath}/modules";  in if it.exists then {
            nixosModules = { default = { imports = builtins.attrValues it.result; }; } // it.result;
        } else { })
    )); in if (builtins.isList result) then mergeFlakeOutputs result else result;

    # Combines »patchFlakeInputs« and »importRepo« in a single call. E.g.:
    # outputs = inputs: let patches = {
    #     nixpkgs = [
    #         # remote: { url = "https://github.com/NixOS/nixpkgs/pull/###.diff"; sha256 = inputs.nixpkgs.lib.fakeSha256; }
    #         # local: ./overlays/patches/nixpkgs-###.patch # (use long native path to having the path change if any of the other files in ./. change)
    #     ]; # ...
    # }; in inputs.functions.lib.patchFlakeInputsAndImportRepo inputs patches ./. (inputs@{ self, nixpkgs, ... }: repo@{ nixosModules, overlays, lib, ... }: let ... in [ repo ... ])
    patchFlakeInputsAndImportRepo = inputs: patches: flakePath: outputs: (
        patchFlakeInputs inputs patches (inputs: importRepo inputs flakePath (outputs (inputs // {
            self = inputs.self // { outPath = builtins.path { path = flakePath; name = "source"; }; }; # If the »flake.nix is in a sub dir of a repo, "${inputs.self}" would otherwise refer to the parent. (?)
        })))
    );

    # Merges a list of flake output attribute sets.
    mergeFlakeOutputs = outputList: builtins.zipAttrsWith (type: values: (
        if ((builtins.length values) == 1) then (builtins.head values)
        else if (builtins.all builtins.isAttrs values) then (builtins.zipAttrsWith (system: values: mergeAttrsUnique values) values)
        else throw "Outputs.${type} has multiple values which are not all attribute sets, can't merge."
    )) outputList;

}
