{ description = ''
    A collection of Nix (language) functions.
''; inputs = {
    nixpkgs = { url = "github:NixOS/nixpkgs/nixos-24.05"; };
}; outputs = inputs: let
    dirname = builtins.path { path = ./.; name = "source"; };
in {
    lib = import "${dirname}/lib" "${dirname}/lib" inputs;
}; }
