{ description = ''
    A collection of Nix (language) functions.
''; inputs = {
    nixpkgs = { url = "github:NixOS/nixpkgs/nixos-23.11"; };
}; outputs = inputs: let
    dirname = builtins.path { path = ./.; name = "source"; };
in {
    lib = import "${dirname}/lib" "${dirname}/lib" inputs;
}; }
