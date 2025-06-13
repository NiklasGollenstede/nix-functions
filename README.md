
# Nix Functions

A collection of Nix language functions.
The functions are defined in [`./lib/`](./lib/) and are each individually documented there.

[`./lib/flakes.nix`](./lib/flakes.nix) defines functions that help when writing Nix flakes (inputs, internal structure, outputs) -- see [`./example/template/`](./example/template/) for a usage example.
[`./lib/imports.nix`](./lib/imports.nix) provides some lower-level import logic.
[`./lib/scripts.nix`](./lib/scripts.nix) defines functions that can be used to generate (bash) scripts; `substituteImplicit` provides a structured way to use Nix values in bash scripts.
The functions in [`./lib/vars.nix`](./lib/vars.nix) do all sorts of Nix value transformations, and [`./lib/misc.nix`](./lib/misc.nix) contains the few things that didn't fit in any of the other categories.


## Basic Usage

`flake.nix`:
```nix
{ inputs = {
    functions.url = "github:NiklasGollenstede/nix-functions";
}; outputs = inputs@{ functions, }: {
    # all the functions defined in the ./lib/*.nix files a are available as functions.lib.*
}; }
```
[`./example/template/`](./example/template/) shows a comprehensive example of how to use these functions to create a Nix flake repository where inputs are automatically made available everywhere, and the different parts are automatically imported and exported as flake outputs, with quite little boilerplate.


## License

All files in this repository ([`nix-functions`](https://github.com/NiklasGollenstede/nix-functions)) (except LICENSE) are authored by the authors of this repository, and are copyright 2022 - present Niklas Gollenstede.

This software may be used under the terms of the MIT license, as detailed in [`./LICENSE`](./LICENSE).
