
# Automatic Flake Imports

The functions in [`./flakes.nix`](./flakes.nix) help with patching flake inputs, importing your own files in a structured way, and providing flake outputs.
Here is an example how `patchFlakeInputsAndImportRepo`, which combines these things, can be used across a repository:

`flake.nix`:
```nix
{ inputs = {
    nixpkgs = { url = "github:NixOS/nixpkgs/nixos-23.05"; };
    functions = { url = "github:NiklasGollenstede/nix-functions"; inputs.nixpkgs.follows = "nixpkgs"; };
}; outputs = inputs: let patches = {
    nixpkgs = [ # patches will automatically be applied to the respective inputs (below)
        # remote: { url = "https://github.com/NixOS/nixpkgs/pull/###.diff"; sha256 = inputs.nixpkgs.lib.fakeSha256; }
        # local: ./overlays/patches/nixpkgs-###.patch # (use native (unquoted) path to the file itself, so that the patch has its own nix store path, which only changes if the patch itself changes (and not if any of the other files in ./. change))
    ]; # ...
}; in inputs.functions.lib.patchFlakeInputsAndImportRepo inputs patches ./. (inputs@{ self, nixpkgs, ... }: repo@{
    nixosModules, # import ./modules/ (if it exists) and create a default module including all the others
    overlays, # import ./overlays/ (if it exists) and create a default overlay applying all the others
    lib, # import ./lib/ (if it exists)
... }: let
    inherit (lib) my; # your own library functions
    inherit (lib) fun; # functions provided by this flake
in [ # can return a list of attrsets, which will be merged
    repo # export the lib.* nixosModules.* overlays.* imported from this repo

    (functions.forEachSystem [ "aarch64-linux" "x86_64-linux" ] (localSystem: let
        pkgs = functions.importPkgs inputs { system = localSystem; }; # this automatically uses any »inputs.*.overlays.default«
    in {
        packages = functions.getModifiedPackages pkgs overlays; # this selects any packages that the (own) »overlays« touch
        defaultPackage = self.packages.${localSystem}.somethingImportant;
    }))
]); }
```

`lib/default.nix`:
```nix
dirname: inputs@{ self, nixpkgs, functions, ...}: let
    categories = functions.lib.importAll inputs dirname;
    my = (builtins.foldl' (a: b: a // (if builtins.isAttrs b then b else { })) { } (builtins.attrValues categories)) // categories;
in nixpkgs.lib // { fun = functions.lib; inherit my; }
```
`lib/one.nix`:
```nix
dirname: inputs@{ self, nixpkgs, functions, ...}: let
    inherit (nixpkgs) lib; fun = functions.lib;
    inherit (import "${dirname}/two.nix" dirname inputs) more helpers;
in rec {
    example = arg1: arg2: arg1 // arg2;
    # ...
}
```
...

`modules/default.nix`:
```nix
dirname: inputs: inputs.functions.importModules inputs dirname { }
```
`modules/one.nix.md`:
````md
/*
# NixOS Module
## Implementation
```nix
#*/# end of MarkDown, beginning of NixOS module:
dirname: inputs: { config, pkgs, lib, ... }: let inherit (inputs.self) lib; in let
    cfg = config.my.cool.option;
    inherit (lib) my fun;
in {
    options.my = { cool.option = {
        enable = lib.mkEnableOption "TODO: what";
    }; };
    config = lib.mkIf cfg.enable (lib.mkMerge [ ({
        # TODO: implementation
    }) ]);
}
````
`modules/two/default.nix`:
```nix
dirname: inputs: inputs.functions.importModules inputs dirname { }
```
...

`overlays/default.nix`:
```nix
dirname: inputs: inputs.functions.importOverlays inputs dirname { }
```
`overlays/one.nix.md`:
````md
/*
# `nixpkgs` Overlay
## Implementation
```nix
#*/# end of MarkDown, beginning of NixPkgs overlay:
dirname: inputs: final: prev: let
    inherit (final) pkgs; inherit (inputs.self) lib;
    inherit (lib) my fun;
in {
    program-patched = prev.program.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
            ../patches/program-....patch
        ];
    });
}
````
`overlays/two/default.nix`:
```nix
dirname: inputs: inputs.functions.importOverlays inputs dirname { }
```
...
