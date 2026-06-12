{ description = ''
    A collection of Nix (language) functions.
''; inputs = {

    nixpkgs = { url = "github:nix-community/nixpkgs.lib/master"; }; # This flake itself uses only `.lib` from `nixpkgs`, but it is fine to have this "follow" the full nixpkgs when importing from another flake.

}; outputs = inputs: let patches = {

    # We do not actually want to apply any patches (and applying would also not work without full `nixpkgs`),
    nixpkgs = [ (throw "Should never be evaluated for functions") ]; # but this is a good demonstration that accessing/exporting `.lib` bypasses the patching (mostly for performance reasons, and because patching is not usually useful for `.lib`).

}; in (
    let dirname = builtins.path { path = ./.; name = "source"; }; in import "${dirname}/lib/flakes.nix" "${dirname}/lib" inputs # in any other flake, this would simply be `inputs.functions.lib`
).patchFlakeInputsAndImportRepo inputs patches ./. (inputs: repo: [

    repo # exports `./lib` as `.lib` (and nothing else in this repo)

    { templates.default = { path = "${inputs.self}/example/template"; description = "Automatically imported/exported Nix flake repository"; }; }

]); }
