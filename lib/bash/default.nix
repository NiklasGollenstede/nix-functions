dirname: inputs: let
    inherit (import "${dirname}/../imports.nix" dirname inputs) getFilesExt;
    files = getFilesExt "sh(.md)?" dirname;
in files // { asVars = inputs.nixpkgs.lib.mapAttrs' (name: value: { name = builtins.replaceStrings ["-"] ["_"] name; inherit value; }) files; }
