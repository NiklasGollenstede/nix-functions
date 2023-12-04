dirname: inputs: let
    inherit (import "${dirname}/../imports.nix" dirname inputs) getFilesExt;
in getFilesExt "sh(.md)?" dirname
