{ description = (
    "TODO: short description here. And your contents below."
); inputs = {
	nixpkgs = { url = "github:NixOS/nixpkgs/nixos-25.05"; };
	functions = { url = "github:NiklasGollenstede/nix-functions"; inputs.nixpkgs.follows = "nixpkgs"; };
    systems.url = "github:nix-systems/default-linux";
}; outputs = inputs: let patches = {
	nixpkgs = [ # patches will automatically be applied to the respective inputs (below)
		# remote: { url = "https://github.com/NixOS/nixpkgs/pull/###.diff"; sha256 = inputs.nixpkgs.lib.fakeSha256; }
		# local: ./overlays/patches/nixpkgs-###.patch # (use native (unquoted) path to the file itself, so that the patch has its own nix store path, which only changes if the patch itself changes (and not if any of the other files in ./. change))
	]; # ...
}; in inputs.functions.lib.patchFlakeInputsAndImportRepo inputs patches ./. (inputs@{ self, nixpkgs, functions, ... }: repo@{
	lib, # imported »./lib/« (if it exists), see »importLib«
	nixosModules, # »./modules/« (»default.nix« or all ».nix(.md)« files and dirs) imported, with a default module that includes all the others
	patches, # »./patches/path/to/my.patch« as »path.to.my«
	overlays, # imported »./overlays/« (»default.nix« or all ».nix(.md)« files), plus derived from «./pkgs/« and ».patches«, with a default overlay applying all the others
	packages, legacyPackages, # derived from the ».overlays«
... }: let
	inherit (lib) my; # your own library functions
	inherit (lib) fun; # functions provided by this flake
in [ # can return a list of attrsets, which will be merged
	repo # export the lib.* nixosModules.* overlays.* patches.* and (legacy)packages.*.* imported from this repo

    # But can also add custom exports:
	{ apps = (functions.lib.exportFromPkgs { inherit inputs; what = pkgs: { # For each »inputs.systems« (or x64/aarch64-linux/darwin). Automatically uses any »inputs.*.overlays.default«.
		format = pkgs.writeShellScriptBin "..." ''...'';
		default = pkgs.somethingImportantThatOurOwnOverlayAdded;
	}; asApps = true; }); } # wrap for export as apps (to be run) instead of (legacy)packages (to be installed)
]); }
