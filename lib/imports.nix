dirname: inputs@{ self, nixpkgs, ...}: let
    inherit (nixpkgs) lib;
    inherit (import "${dirname}/vars.nix" dirname inputs) mapMerge mapMergeUnique mergeAttrsUnique mergeAttrsRecursive endsWith;
    inherit (import "${dirname}/scripts.nix" dirname inputs) substituteImplicit;
    #inherit (import "${dirname}/misc.nix" dirname inputs) trace;
    bash = import "${dirname}/bash" "${dirname}/bash" inputs;
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
        # Whether the import path points to an existing nix file that accepts the wrapping arguments:
        exists = (isImplicitDir || (builtins.pathExists (if isExplicit then path else "${path}.nix"))) && (let imported = import fullPath; in builtins.isFunction imported && builtins.functionArgs imported == { } && builtins.isFunction (imported ""));
        # Return »null« if not ».exists«:
        optional = if exists then result else null;
        # Throw if not ».exists«:
        required = if exists then result else throw (if isExplicit then "File ${path} can not be imported as wrapped nix file" else "Neither ${path}/default.nix nor ${path}.nix can be imported as wrapped nix file");
        # ».result« interpreted as NixOS module, wrapped to preserve the import path:
        module = { _file = fullPath; imports = [ required ]; }; # == lib.setDefaultModuleLocation fullPath required
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
    # { "a" = <wrapped>; "b" = <wrapped>; "c/d" = <wrapped>; "c/e" = <wrapped>; }
    importFilteredFlattened = dir: inputs: { except ? [ ], filter ? (thing: true), default ? null, wrap ? (path: thing: thing), merge ? null, }: let
        dirs = builtins.mapAttrs (__: _: null) (lib.filterAttrs (__: _:_ == "directory") (builtins.readDir dir));
        files = getNixFiles dir;
    in mapMergeUnique (name: path: let
        thing = if path == null then if default == null then null else default "${dir}/${name}" else (importWrapped inputs path).optional;
        merge' = thing.__mergeMode or merge;
    in if thing != null && filter thing then (
        { ${name} = wrap path thing; }
    ) else (if (builtins.isAttrs thing) && merge' == "splice" then (
        builtins.removeAttrs (lib.filterAttrs (_: filter) thing) [ "__mergeMode" ] # (TODO: filtering is not recursive)
    ) else if (builtins.isAttrs thing) then (
        mapMerge (name': thing': if (filter thing') then (
            { "${name}/${name'}" = thing'; }
        ) else { }) thing
    ) else { })) (builtins.removeAttrs (dirs // files) except);

    # Used in »lib/default.nix«, this imports library local library functions and bundles them for exporting as »lib« flake output and local use. Additionally, it imports the ».lib«s defined by input flakes and prepares those and the local library functions for consumption by the local flake.
    # Each nix file/dir in »lib/« (not listed in »except«) will be imported and added as »lib.${name}« (w/o extension). Additionally, if the imported value is an attribute set and »name« is not in »noSpread«, then the values attributes will be added directly to lib.
    # Internally, the calling flake can use »lib = inputs.self.lib.__internal__«, which is »inputs.nixpkgs.lib« (i.e, the nix standard library), with the ».lib« output of all »inputs« (including the own lib as »self«) added.
    # By passing e.g. »rename.too-long = "foo"«, inputs.too-long.lib« will (internally) become »lib.foo«.
    importLib = inputs: dir: { except ? [ ], noSpread ? [ ], rename ? { }, ... }: let
        categories = builtins.removeAttrs (importAll inputs dir) except;
        self = (mergeAttrsUnique (builtins.filter (it: builtins.isAttrs it && !it?__functor) (builtins.attrValues (builtins.removeAttrs categories noSpread)))) // categories;
        inputs' = builtins.removeAttrs inputs [ "self" ];
        reexports = builtins.listToAttrs (builtins.filter (_:_.name != null) (map (name: { name = if name == "nixpkgs" || !inputs.${name}?lib then null else rename.${name} or name; value = inputs.${name}.lib; }) (builtins.attrNames inputs')));
    in self // { __internal__ = nixpkgs.lib // reexports // { ${rename.self or "self"} = self; }; };

    # Used in a »default.nix« and called with the »dir« it is in, imports all modules in that directory as an attribute set. Importing automatically recurses into directories without explicit »default.nix«. See »importFilteredFlattened« and »isProbablyModule« for details.
    importModules = inputs: dir: opts: importFilteredFlattened dir inputs ({
        except = [ "default" ]; default = dir: importModules inputs dir opts;
    } // opts // { filter = isProbablyModule; wrap = path: module: { _file = path; imports = [ module ]; }; });

    # Used in a »default.nix« and called with the »dir« it is in, imports all overlays in that directory as an attribute set. Importing automatically recurses into directories without explicit »default.nix«. See »importFilteredFlattened« and »couldBeOverlay« for details.
    importOverlays = inputs: dir: opts: importFilteredFlattened dir inputs ({
        except = [ "default" ]; default = dir: importOverlays inputs dir opts;
    } // opts // { filter = couldBeOverlay; });

    # Used in a »default.nix« and called with the »dir« it is in, this returns an attribute set of all patch files in that directory as (see »getPatchFiles«). Importing automatically recurses into directories without explicit »default.nix«. Any explicit »*/default.nix« found in »dir« will be imported and added to the result as well, so this function can be used in nested »default.nix«es recursively.
    importPatches = inputs: dir: opts: ( # (recurse implicitly)
        builtins.mapAttrs (name: _: importPatches inputs "${dir}/${name}" opts) (lib.filterAttrs (__: _:_ == "directory") (builtins.removeAttrs (builtins.readDir dir) (opts.except or [ ])))
    ) // ( # (recurse explicitly)
        builtins.mapAttrs (name: path: import path "${dir}/${name}" inputs) (builtins.removeAttrs (getNixDirs dir) (opts.except or [ ]))
    ) // (getPatchFiles dir); # (actual import)

    # Used in a »default.nix« and called with the »dir« it is in, imports all package definitions in that directory as an attribute set. Importing automatically recurses into directories without explicit »default.nix«. Any nix file that returns a function is considered a package definition. See »importFilteredFlattened«.
    importPkgsDefs = inputs: dir: opts: importFilteredFlattened dir inputs ({
        except = [ "default" ]; default = dir: importPkgsDefs inputs dir opts;
    } // opts // { filter = builtins.isFunction; });

    importScripts = inputs: dir: opts: ( # (recurse implicitly)
        builtins.mapAttrs (name: _: importScripts inputs "${dir}/${name}" opts) (lib.filterAttrs (__: _:_ == "directory") (builtins.removeAttrs (builtins.readDir dir) (opts.except or [ ])))
    ) // ( # (recurse explicitly)
        builtins.mapAttrs (name: path: import path "${dir}/${name}" inputs) (builtins.removeAttrs (getNixDirs dir) (opts.except or [ ]))
        # (actual import:)
    ) // (lib.mapAttrs (name: path: ({
        writeShellScriptBin, pkgs, lib, helpers ? { },
        context ? { }, preScript ? "", postScript ? "",
    }: let
        scripts = substituteImplicit { inherit helpers pkgs; scripts = [ path ]; context = {
            dirname = dir; inherit inputs pkgs lib; outputs = inputs.self;
        } // (opts.context or { }) // context; };
    in (
        (writeShellScriptBin name ''
            source ${bash.generic-arg-parse}
            source ${bash.generic-arg-verify}
            source ${bash.generic-arg-help}
            ${preScript} ${"\n"} ${scripts} ${"\n"} ${postScript}
        '').overrideAttrs (old: { passthru = { inherit scripts; src = path; }; })
    ))) (getFilesExt "sh(.md)?" dir));

    # Imports »inputs.nixpkgs« and instantiates it with all default ».overlay(s)« provided by »inputs.*«.
    importPkgs = inputs: args: import inputs.nixpkgs ({
        overlays = getOverlaysFromInputs inputs;
    } // args);

    # Given an attrset of nix flake »inputs«, returns the list of all default overlays defined by those other flakes (non-recursive).
    getOverlaysFromInputs = inputs: (lib.remove null (map (input: if input?overlays.default then input.overlays.default else if input?overlay then input.overlay else null) (builtins.attrValues inputs)));

    # Given an attrset of nix flake »inputs«, returns the list of all default NixOS modules defined by those other flakes (non-recursive).
    getModulesFromInputs = inputs: (lib.remove null (map (input: if input?nixosModules.default then input.nixosModules.default else if input?nixosModule then input.nixosModule else null) (builtins.attrValues inputs)));

    # Given a list of »overlays« and »pkgs« with them applied, returns the subset (of derivations and things that contain derivations) of »pkgs« that was directly modified (returned) by the overlays.
    # (But this only works for top-level / non-scoped packages.)
    getModifiedPackages = pkgs: overlays: let
        getNames = overlay: builtins.attrNames (overlay pkgs pkgs);
        names = if overlays?default then getNames overlays.default else builtins.concatLists (map getNames (builtins.attrValues overlays));
    in mapMergeUnique (name: if pkgs.${name}?recurseForDerivations || lib.isDerivation pkgs.${name} then { ${name} = pkgs.${name}; } else { }) names;

    # Automatically builds a flakes »outputs.packages« based on its »(inputs.self == outputs).overlays.default/.*« (and »inputs.nixpkgs«).
    packagesFromOverlay = args@{ inputs, systems ? if inputs?systems then import inputs.systems else defaultSystems, default ? null, extra ? pkgs: { }, exclude ? [ ], apply ? pkgs: packages: packages, ... }: lib.genAttrs systems (localSystem: let
        pkgs = importPkgs inputs ((builtins.removeAttrs args [ "inputs" "systems" "overlays" "default" "extra" "exclude" ]) // { system = localSystem; });
        modifiedPackages = getModifiedPackages pkgs (inputs.self.overlays or { default = inputs.self.overlay; });
        compatiblePackages = lib.filterAttrs (_: pkg: !(builtins.isList (pkg.meta.platforms or null)) || (builtins.elem localSystem pkg.meta.platforms)) modifiedPackages;
        withExtras = (builtins.removeAttrs compatiblePackages exclude)
        // (if lib.isList extra then builtins.listToAttrs (map (name: { inherit name; value = pkgs.${name}; }) extra) else extra pkgs)
        // (if default != null then { default = default pkgs; } else { });
    in apply pkgs withExtras);

    # Automatically instantiates »input.nixpkgs« for all »systems« (see »importPkgs inputs args«), and returns a subset of it (as listed in or returned by »what«, plus »default«) for exporting as »programs« or (wrapped) as »apps« flake output.
    exportFromPkgs = args@{ inputs, systems ? if inputs?systems then import inputs.systems else defaultSystems, default ? null, what ? [ ], asApps ? false, ... }: lib.genAttrs systems (localSystem: let
        pkgs = importPkgs inputs ((builtins.removeAttrs args [ "inputs" "systems" "default" "what" ]) // { system = localSystem; });
        packages = (if builtins.isList what then builtins.listToAttrs (map (name: { inherit name; value = pkgs.${name}; }) what) else what pkgs)
        // (if default != null then { default = if builtins.isString default then pkgs.${default} else default pkgs; } else { });
    in if asApps then builtins.mapAttrs (_: pkg: let bin = pkg.bin or pkg.out or pkg; in { type = "app"; program = if pkg.meta?mainProgram then "${bin}/bin/${pkg.meta.mainProgram}" else "${bin}"; derivation = pkg; }) packages else packages);

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

    ## Evaluates a NixOS module (plus a bit of (input) config for it) in isolation, with the goal that the (output) config created by that module may be retrieved.
    #  The exact semantics and API of this are still subject to change.
    evalNixpkgsModule = specialArgs: module: config: lib.evalModules {
        modules = [
            { config._module.args = { inherit lib; } // specialArgs; }
            #{ config._module.freeformType = lib.types.attrsOf lib.types.anything; } # infinite recursion
            { options = lib.genAttrs [ "appstream" "assertions" "boot" "console" "containers" "docker-containers" "documentation" "dysnomia" "ec2" "environment" "fileSystems" "fonts" "gtk" "hardware" "home-manager" "i18n" "ids" "jobs" "krb5" "lib" "location" "meta" "nesting" "networking" "nix" "nixops" "nixpkgs" "oci" "openstack" "passthru" "power" "powerManagement" "preface" "profiles" "programs" "qt" "qt5" "security" "services" "snapraid" "sound" "specialisation" "stubby" "swapDevices" "system" "systemd" "time" "users" "virtualisation" "warnings" "xdg" "zramSwap" ] (root: lib.mkOption { type = lib.types.anything; }); } # only things in this list may be set in »config« but they then can't be defined as »options« # TODO: can lib.mergeModules be used to help with this?
            module { inherit config; }
        ];
    };

}
