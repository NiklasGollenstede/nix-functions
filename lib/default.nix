dirname: inputs: let
    categories = (import "${dirname}/imports.nix" dirname inputs).importAll inputs dirname;
in (builtins.foldl' (a: b: a // (if builtins.isAttrs b then b else { })) { } (builtins.attrValues categories)) // categories
