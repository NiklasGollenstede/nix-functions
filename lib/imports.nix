dirname: inputs@{ self, nixpkgs, ...}: let
    inherit (nixpkgs) lib;
    inherit (import "${dirname}/vars.nix" dirname inputs) mapMergeUnique mergeAttrsRecursive endsWith;
    inherit (import "${dirname}/misc.nix" dirname inputs) trace;
    defaultSystems = [ "aarch64-linux" "aarch64-darwin" "x86_64-linux" "x86_64-darwin" ];
in rec {

    # Builds an attrset that, for each file with extension »ext« in »dir«, maps the the base name of that file, to its full path.
    getFilesExt = ext: dir: builtins.removeAttrs (builtins.listToAttrs (map (name: let
        match = builtins.match ''^(.*)[.]${builtins.replaceStrings [ "." ] [ "[.]" ] ext}$'' name;
    in if (match != null) then {
        name = builtins.head match; value = "${dir}/${name}";
    } else { name = ""; value = null; }) (builtins.attrNames (builtins.readDir dir)))) [ "" ];


    # Builds an attrset that, for each folder that contains a »default.nix«, and for each ».nix« or ».nix.md« file, in »dir«, maps the the name of that folder, or the name of the file without extension(s), to its full path.
    getNixFiles = dir: mapMergeUnique (name: type: if (type == "directory") then (
        if (builtins.pathExists "${dir}/${name}/default.nix") then { ${name} = "${dir}/${name}/default.nix"; } else { }
    ) else (
        let
            match = builtins.match ''^(.*)[.]nix([.]md)?$'' name;
        in if (match != null) then {
            ${builtins.head match} = "${dir}/${name}";
        } else { }
    )) (builtins.readDir dir);
    # Builds an attrset that, for each folder that contains a »default.nix« in »dir«, maps the the name of that folder to its full path.
    getNixDirs = dir: mapMergeUnique (name: type: if (type == "directory") then (
        if (builtins.pathExists "${dir}/${name}/default.nix") then { ${name} = "${dir}/${name}/default.nix"; } else { }
    ) else { }) (builtins.readDir dir);

    getNixFilesRecursive = dir: let
        list = prefix: dir: mapMergeUnique (name: type: if (type == "directory") then (
            list "${prefix}${name}/" "${dir}/${name}"
        ) else (let
            match = builtins.match ''^(.*)[.]nix([.]md)?$'' name;
        in if (match != null) then {
            "${prefix}${builtins.head match}" = "${dir}/${name}";
        } else { })) (builtins.readDir dir);
    in list "" dir;

    # Returns an attrset where the values are the paths to all ».patch« files in this directory, and the names the respective »basename -s .patch«s.
    getPatchFiles = dir: builtins.removeAttrs (builtins.listToAttrs (map (name: let
        match = builtins.match ''^(.*)[.]patch$'' name;
    in if (match != null) then {
        name = builtins.head match; value = builtins.path { path = "${dir}/${name}"; inherit name; }; # »builtins.path« puts the file in a separate, content-addressed store path, ensuring it's path only changes when the content changes, thus avoiding unnecessary rebuilds.
    } else { name = ""; value = null; }) (builtins.attrNames (builtins.readDir dir)))) [ "" ];

    ## Decides whether a thing is probably a NixOS configuration module or not.
    #  Probably because almost everything could be a module declaration (any attribute set or function returning one is potentially a module).
    #  Per convention, modules (at least those declared stand-alone in a file) are declared as functions taking at least the named arguments »config«, »pkgs«, and »lib«. Once entered into the module system, to remember where they came from, modules get wrapped in an attrset »{ _file = "<path>"; imports = [ <actual_module> ]; }«.
    isProbablyModule = thing: let args = builtins.functionArgs thing; in (
        (builtins.isFunction thing) && (builtins.isAttrs (thing args)) && (builtins.isBool (args.config or null)) && (builtins.isBool (args.lib or null)) && (builtins.isBool (args.pkgs or null))
    ) || (
        (builtins.isAttrs thing) && ((builtins.attrNames thing) == [ "_file" "imports" ]) && ((builtins.isString thing._file) || (builtins.isPath thing._file)) && (builtins.isList thing.imports)
    );

    ## Decides whether a thing could be a NixPkgs overlay.
    #  Any function with two (usually unnamed) arguments returning an attrset could be an overlay, so that's rather vague.
    couldBeOverlay = thing: let result1 = thing (builtins.functionArgs thing); result2 = result1 (builtins.functionArgs result1); in builtins.isFunction thing && builtins.isFunction result1 && builtins.isAttrs result2;

    # Builds an attrset that, for each folder (containing a »default.nix«) or ».nix« or ».nix.md« file (other than »./default.nix«) in this folder, as the name of that folder or the name of the file without extension(s), exports the result of importing that file/folder.
    importAll = inputs: dir: builtins.mapAttrs (name: path: import path (if endsWith "/default.nix" path then "${dir}/${name}" else dir) inputs) (builtins.removeAttrs (getNixFiles dir) [ "default" ]);

    # Import a Nix file that expects the standard `dirname: inputs: ` arguments, providing some additional information and error handling.
    importWrapped = inputs: path': let path = "${path'}"; in rec {
        # Whether the file is imported by an explicit full path (or one omitting ».nix« or »/default.nix«):
        isExplicit = (builtins.match ''^(.*)[.]nix([.]md)?$'' path) != null;
        # Whether the import path _implicitly_ refers to the »/default.nix« in a directory:
        isImplicitDir = !isExplicit && builtins.pathExists "${path}/default.nix";
        # The resolved path that will be imported:
        fullPath = if isImplicitDir then "${path}/default.nix" else if isExplicit then path else "${path}.nix";
        # The imported nix value:
        result = import fullPath (if isImplicitDir then path else builtins.dirOf path) inputs;
        # Whether the import path points to an existing file:
        exists = isImplicitDir || (builtins.pathExists (if isExplicit then path else "${path}.nix"));
        # Return »null« if not ».exists«:
        optional = if exists then result else null;
        # Throw if not ».exists«:
        required = if exists then result else throw (if isExplicit then "File ${path} does not exist" else "Neither ${path}/default.nix nor ${path}.nix exist");
        # ».result« interpreted as NixOS module, wrapped to preserve the import path:
        module = { _file = fullPath; imports = [ required ]; };
    };

    ## Returns an attrset that, for each file in »dir« (except ...), imports that file and exposes only if the result passes »filter«. If provided, the imported value is »wrapped« after filtering.
    #  If a file/folder' import that is rejected by »filter« is an attrset (for example because it results from a call to this function), then all attributes whose values pass »filter« are prefixed with the file/folders name plus a slash and merged into the overall attrset.
    #  Example: Given a file tree like this, where each »default.nix« contains only a call to this function with the containing directory as »dir«, and every other file contains a definition of something accepted by the »filter«:
    #     ├── default.nix
    #     ├── a.nix.md
    #     ├── b.nix
    #     └── c
    #         ├── default.nix
    #         ├── d.nix
    #         └── e.nix.md
    # The top level »default.nix« returns:
    # { "a" = <filtered>; "b" = <filtered>; "c/d" = <filtered>; "c/e" = <filtered>; }
    importFilteredFlattened = dir: inputs: { except ? [ ], filter ? (thing: true), wrap ? (path: thing: thing), }: let
        files = builtins.removeAttrs (getNixFiles dir) except;
    in mapMergeUnique (name: path: let
        thing = import path (if endsWith "/default.nix" path then "${dir}/${name}" else dir) inputs;
    in if (filter thing) then (
        { ${name} = wrap path thing; }
    ) else (if (builtins.isAttrs thing) then (
        mapMergeUnique (name': thing': if (filter thing') then (
            { "${name}/${name'}" = thing'; }
        ) else { }) thing
    ) else { })) files;

    # Used in a »default.nix« and called with the »dir« it is in, imports all modules in that directory as an attribute set. See »importFilteredFlattened« and »isProbablyModule« for details.
    importModules = inputs: dir: opts: importFilteredFlattened dir inputs ({ except = [ "default" ]; } // opts // { filter = isProbablyModule; wrap = path: module: { _file = path; imports = [ module ]; }; });

    # Used in a »default.nix« and called with the »dir« it is in, imports all overlays in that directory as an attribute set. See »importFilteredFlattened« and »couldBeOverlay« for details.
    importOverlays = inputs: dir: opts: importFilteredFlattened dir inputs ({ except = [ "default" ]; } // opts // { filter = couldBeOverlay; });

    # Used in a »default.nix« and called with the »dir« it is in, this returns an attribute set of all patch files in that directory as (see »getPatchFiles«). Any »*/default.nix« found in »dir« will be imported and added to the result as well, so this function can be used in nested »default.nix«es recursively.
    importPatches = inputs: dir: opts: (lib.mapAttrs (name: path: import path "${dir}/${name}" inputs) (builtins.removeAttrs (getNixDirs dir) (opts.except or [ ]))) // (getPatchFiles dir);

    # Imports »inputs.nixpkgs« and instantiates it with all default ».overlay(s)« provided by »inputs.*«.
    importPkgs = inputs: args: import inputs.nixpkgs ({
        overlays = getOverlaysFromInputs inputs;
    } // args);

    # Given an attrset of nix flake »inputs«, returns the list of all default overlays defined by those other flakes (non-recursive).
    getOverlaysFromInputs = inputs: (lib.remove null (map (input: if input?overlays.default then input.overlays.default else if input?overlay then input.overlay else null) (builtins.attrValues inputs)));

    # Given an attrset of nix flake »inputs«, returns the list of all default NixOS modules defined by those other flakes (non-recursive).
    getModulesFromInputs = inputs: (lib.remove null (map (input: if input?nixosModules.default then input.nixosModules.default else if input?nixosModule then input.nixosModule else null) (builtins.attrValues inputs)));

    # Given a list of »overlays« and »pkgs« with them applied, returns the subset of »pkgs« that was directly modified by the overlays.
    # (But this only works for top-level / non-scoped packages.)
    getModifiedPackages = pkgs: overlays: let
        getNames = overlay: builtins.attrNames (overlay pkgs pkgs);
        names = if overlays?default then getNames overlays.default else builtins.concatLists (map getNames (builtins.attrValues overlays));
    in mapMergeUnique (name: if lib.isDerivation pkgs.${name} then { ${name} = pkgs.${name}; } else { }) names;

    # Automatically builds a flakes »outputs.packages« based on its »(inputs.self == outputs).overlays.default/.*« (and »inputs.nixpkgs«).
    packagesFromOverlay = args@{ inputs, systems ? if inputs?systems then import inputs.systems else defaultSystems, default ? null, extra ? [ ], exclude ? [ ], ... }: lib.genAttrs systems (localSystem: let
        pkgs = importPkgs inputs ((builtins.removeAttrs args [ "inputs" "systems" "overlays" "default" "extra" "exclude" ]) // { system = localSystem; });
        packages = getModifiedPackages pkgs (inputs.self.overlays or { default = inputs.self.overlay; });
    in (builtins.removeAttrs packages exclude)
    // (if lib.isList extra then builtins.listToAttrs (map (name: { inherit name; value = pkgs.${name}; }) extra) else extra pkgs)
    // (if default != null then { default = default pkgs; } else { }));

    # Automatically instantiates »input.nixpkgs« for all »systems« (see »importPkgs inputs args«), and returns a subset of it (as listed in or returned by »what«, plus »default«) for exporting as »programs« or (wrapped) as »apps« flake output.
    exportFromPkgs = args@{ inputs, systems ? if inputs?systems then import inputs.systems else defaultSystems, default ? null, what ? [ ], ... }: lib.genAttrs systems (localSystem: let
        pkgs = importPkgs inputs ((builtins.removeAttrs args [ "inputs" "systems" "default" "what" ]) // { system = localSystem; });
    in (if lib.isList what then builtins.listToAttrs (map (name: { inherit name; value = pkgs.${name}; }) what) else what pkgs)
    // (if default != null then { default = default pkgs; } else { }));

    ## Given a path to a module in »nixpkgs/nixos/modules/«, when placed in another module's »imports«, this adds an option »disableModule.${modulePath}« that defaults to being false, but when explicitly set to »true«, disables all »config« values set by the module.
    #  Every module should, but not all modules do, provide such an option themselves.
    #  This is similar to adding the path to »disabledModules«, but:
    #  * leaves the module's other definitions (options, imports) untouched, preventing further breakage due to missing options
    #  * makes the disabling an option, i.e. it can be changed dynamically based on other config values
    # NOTE: This can only be used once per module import graph (~= NixOS configuration) and »modulePath«!
    makeNixpkgsModuleConfigOptional = modulePath: extraOriginalModuleArgs: args@{ config, pkgs, lib, modulesPath, utils, ... }: let
        fullPath = "${modulesPath}/${modulePath}";
        module = import fullPath (args // extraOriginalModuleArgs);
    in { _file = fullPath; imports = [
        { options.disableModule.${modulePath} = lib.mkOption { description = "Disable the nixpkgs module ${modulePath}"; type = lib.types.bool; default = false; }; }
        (if module?config then (
            module // { config = lib.mkIf (!config.disableModule.${modulePath}) module.config; }
        ) else (
            { config = lib.mkIf (!config.disableModule.${modulePath}) module; }
        ))
        { disabledModules = [ modulePath ]; }
    ]; };

    ## Given a path to a module, and a function that takes the instantiation of the original module and returns a partial module as override, this recursively merges that override onto the original module definition.
    #  Used as an »imports« entry, this allows for much more fine-grained overriding of the configuration (or even other parts) of a module than »makeNixpkgsModuleConfigOptional«, but the override function needs to be tailored to internal implementation details of the original module.
    #  Esp., it is important to know that »mkIf« both existing in the original module and in the return from the override results in an attrset »{ _type="if"; condition; content; }«. Accessing content of an existing »mkIf« thus requires adding ».content« to the lookup path, and the »content« of returned »mkIf«s will get merged with any existing attribute of that name.
    # Also, only use this on modules that are imported by default; otherwise, it gets really confusing if something somewhere imports the module and that has no effect.
    overrideNixpkgsModule = modulePath: extraOriginalModuleArgs: override: args@{ config, pkgs, lib, modulesPath, utils, ... }: let
        fullPath = "${modulesPath}/${modulePath}";
        module = import fullPath (args // extraOriginalModuleArgs);
        overrides = lib.toList (override module);
        _file = if (builtins.head overrides)?config then let pos = builtins.unsafeGetAttrPos "config" (builtins.head overrides); in "${pos.file}:${toString pos.line}(override)" else "${fullPath}#override";
    in { inherit _file; imports = [
        (mergeAttrsRecursive ([ { imports = module.imports or [ ]; options = module.options or { }; config = module.config or { }; } ] ++ overrides))
        { disabledModules = [ modulePath ]; }
    ]; };
}
