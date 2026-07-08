dirname: inputs: let
    inherit (inputs.nixpkgs.sourceInfo.unpatched or inputs.nixpkgs) lib;
    inherit (import "${dirname}/../imports.nix" dirname inputs) getFilesExt;
    files = getFilesExt "sh(.md)?" dirname; # or »./.«?
in files // {
    asVars = lib.mapAttrs' (name: value: { name = builtins.replaceStrings ["-"] ["_"] name; inherit value; }) files;
}
