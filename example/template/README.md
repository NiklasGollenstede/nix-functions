
# Automatically Imported/Exported Nix Flake Repository

This template shows a comprehensive example of how to use the nix `functions` to create a Nix flake repository where inputs are automatically made available everywhere, and the different parts are automatically imported and exported as flake outputs, with quite little boilerplate.


## TODOs (when instantiating this template)

* [ ] rename and populate (or delete) the `example.*` files
* [ ] replace the `description` in `flake.nix`
* [ ] run `nix flake update` to create the `flake.lock`
* [ ] Pick and add a `LICENSE`
* [ ] replace this `README.md` with your own documentation
* [ ] `git init && git add --all`


# About this Template

The (`inputs.functions.`)`flakes.*` functions help with patching flake inputs, importing your own files in a structured way, and providing flake outputs.
The following documents the necessary concepts and conventions behind them and their usage.
The template in this directory provides an example abiding by these conventions, and can be used as a starting point for your own flake repository.


### Rules (/Conventions) for Flake `outputs` (in General)

Flakes are a structured mechanism for Nix repositories to export their products and for others to declare a dependency on and consume those products.
When using flakes, Nix enforces that `flake.nix#imports` is the only point of importing external things (other than hash-pinned URLs).
Nix also defines [a schema](https://nixos.wiki/wiki/Flakes#Flake_schema) for the values of `#outputs` and this `#inputs.*`, but many aspects of the `#outputs` are not enforced or even explicitly stated:

* `flake.nix#outputs` is the only defined export of a flake. Other flakes should not directly access files inside a flake, unless the paths are exported via `#outputs`.
	* Using `${inputs.self}/path/to/file` is ok, `${inputs.other-flake}/path/to/file` is usually not well defined (and a sign that other-flake is not doing its `#outputs` well).
	* Implementing aliases, deprecation notices and other backwards-compatibility fixes is easy in Nix, but not usually done with files.
* Packages (both added and modified) are exported for other flakes via `#outputs.overlays(.*/.default)`.
	* `overlays.default` should contain all packages that other flakes should import by default (the poorly named function (`nixpkgs.`)`lib.composeManyExtensions` can be used to merge overlays).
	* Applying the `.default` overlays of all (direct) inputs can be done in library functions and significantly reduces boilerplate code.
		* Note: There are performance concerns regarding this, but first merging overlays (`composeManyExtensions`) and then passing them to `import nixpkgs` seems to be faster.
* Packages are imported (to `pkgs` instances) via the (`.default`) overlays of input flakes.
	* Inside a flake, wherever a (`nix`)`pkgs` instance exists (overlays, modules, ...) **do not** use other (or own) flake's `#outputs.(legacy)packages.${arch}.*`. This uses a separate nixpkgs instantiation (per dependent flake, evaluation overhead), disables further overlays to those packages, and most likely breaks any sort of cross-architecture building.
* Packages from the overlays may *additionally* be exported as `#outputs.packages.$arch`.
	* This is meant for CLI usage (`nix shell/run/profile`) *only*.
	* Iff the things to be exported are not derivations (e.g. they are sets of derivations or functions), use `#outputs.legacyPackages...` instead.
* Any `#outputs.(nixpkgs/*)Modules` (that declares options or defines configuration) should include its file location.
	* While the concrete value of that location is an implementation detail (see above), it is useful for debugging and it's uniqueness is required for the module system to work properly (deduplication and suppression of modules).
	* Since a module is anything that can be imported by a module, directly exporting paths to the module files (without explicitly `import`ing them) is a valid solution to this.
* Modules should usually not do anything unless they are `.enable`d, and should *never* do anything that can't be reverted.
	* Importing modules is fairly static and can only depend on the top-level module and arguments passed to it (and all modules). `.enable`ing modules is highly flexible, as it, like any other option's value, can depend on the rest of the `config` state. Modules that can't be enabled (or disabled) are not composable.
* `#outputs.(nixpkgs/*)Modules.default` should import all other modules, since importing modules doesn't directly do anything, but gives the configuration the option to enable them.
	* Importing all `.default` (nixos)modules into all (nixos)configurations can be done in library functions and significantly reduces boilerplate code.
		* Note: There are thousands of module files in `nixpkgs`, most of which are imported by default. Adding a few dozens or maybe hundreds imported from other flakes shouldn't slow evaluation down too much. (`nixos-hardware` may be a reasonable exception to this import-everything-by-default.)


### Convention for Flakes' Internal Structure

To have the functions in `functions.flakes.*` and `functions.import.*` automatically import and export things according to the rules above, the layout and code inside the repository should stick to some conventions (that also otherwise make sense for structural reasons).

[`./lib/`](./lib/) may be used to add additional library functions.
Library functions can depend on `inputs.*.lib`, but can't use `pkgs`, as the system architecture is not defined (also see the point on not using `inputs.*.(legacy)packages.${arch}.*` above).
The functions defined here become the `lib` output, and, together with the `lib` export of all inputs, are made available for your own usage as `inputs.self.lib.__internal__` (usually aliased simply as `lib`) in most other Nix files.
This `lib` is at its bases `nixpkgs.lib`, with all inputs' `lib`s (including `self`) added as sub-attribute sets.
The naming of the sub-attributes can be changed, see [`./lib/default.nix`](./lib/default.nix).

[`./modules/`](./modules/) should contain (NixOS) configuration modules.
As stated above, unless you know that everyone who imports your flake will definitely want your modules enabled, they should be disabled by default.
If your modules are meant for something other than NixOS, you should set a top-level `_class` name in each one.
Everything in `./modules/` that roughly looks like a module will automatically be added to the `nixosModules` output, with the path name (minus (`/default`)`.nix`(`.md`)) as attribute name (see `functions.imports.importModules`), and all modules are merged as `nixosModules.default`.

If your flake defines (NixOS) host configurations, then those should be placed in `./hosts/`.
The [`nixos-installer`](https://github.com/NiklasGollenstede/nixos-installer/) repo (among other things) provides a set of functions to automatically import and install hosts from there.

[`./overlays/`](./overlays/) contains nixpkgs overlays that modify existing packages (usually from `nixpkgs`).
Auto-generated overlays from `patches` and `pkgs` (see below) are merged with the explicit `./overlays/` (see `functions.import.importOverlays`), with the later ones overwriting earlier ones of the same name, as `overlays` output, and all these are merged as `overlays.default`.
Additionally, any packages added or modified by any of those overlays are also exported as `packages.<arch>.*` output (see `functions.import.packagesFromOverlay`).
Anything added/modified by overlays that is not a derivation is exported as `legacyPackages.<arch>.*`.

[`./pkgs/`](./pkgs/) contains new package definitions and package-defining functions.
They are automatically added via overlays of and as packages/functions of the same name as the files path's **base** name (minus (`/default`)`.nix`(`.md`), i.e., `pkgs/foo/bar/default.nix` becomes `bar`, and `pkgs/baz.nix.md` becomes `baz`), which then implicitly create `packages.*` outputs (see above).
The package definitions are imported via `pkgs.callPackage` with empty arguments.

[`./patches/`](./patches/) contains patches.
The patch files are recursively added to the `patches` output, with the file path (minus (`/default`)`.patch`) as attribute path (`patches/foo/bar.patch` becomes `patches.foo.bar`, and `patches/baz.patch` becomes `patches.baz`).
The exported patches are also each copied to individual store paths, so that their path hashes only change when the patch changes, not every time anything in the repository changes (see `functions.imports.importPatches` and `.getPatchFiles`).
Also, for each first-level attribute in `patches`, if there is no overlay or `pkgs/` entry of the same name, an overlay is added to the `overlays` output that applies the patch to the package of the same name (if one exists).
Patches can also be applied to the flake inputs' sources via `functions.flakes.patchFlakeInputs`(`AndImportRepo`), see [`./flake.nix`](./flake.nix) for an example.

[`./flake.nix`](./flake.nix) initiates all the automatic importing by calling `functions.flakes.importRepo`.

In all cases of (recursive) automatic importing, if a `default.nix` file exists in the directory, that is imported instead (and possibly merged with the other imports from the parent directory)
