dirname: { self, nixpkgs, ...}: let
    inherit (nixpkgs) lib;
in rec {

    # takes a V2 (check and) merge function and wraps it to be compatible with the old API
    mkMergeV2Compat = merge: { __functor = self: loc: defs: (self.v2 { inherit loc defs; }).value; v2 = merge; };

    # Applied to a `types.submodule(With)` instance, adds `._module.{options,...}` metadata to the result for debugging and introspection (esp. on the individual instances when used in conjunction with `listOf`/`attrsOf`):
    types.addArgsToSubmodule = submoduleType: submoduleType // (let
        inherit (submoduleType.functor.payload) modules specialArgs class shorthandOnlyDefinesConfig;
        base = lib.modules.evalModules { inherit class specialArgs modules; };
        allModules = defs: map ({ value, file }: if lib.isAttrs value && shorthandOnlyDefinesConfig then { _file = file; config = value; } else { _file = file; imports = [ value ]; }) defs;
    in {
        merge = mkMergeV2Compat ({ loc, defs }: let
            configuration = base.extendModules { modules = [ { _module.args.name = lib.lists.last loc; } ] ++ allModules defs; prefix = loc; };
        in {
            headError = lib.types.checkDefsForError submoduleType.check loc defs;
            value = configuration.config // { _module = configuration._module // { _type = "moduleMeta"; inherit (configuration) extendModules options type; }; }; # (this is the only thing that is not copied straight from 25.11)
            valueMeta = { inherit configuration; };
        });
    });

    # Same. Much less verbose, but requires merge.v2 in 25.11:
    types.addArgsToSubmodule' = submoduleType: submoduleType {
        merge = mkMergeV2Compat (args: let
            result = submoduleType.merge.v2 args;
            inherit (result.valueMeta.configuration) configuration;
        in result // {
            value = result.value // { _module = configuration._module // { _type = "moduleMeta"; inherit (configuration) extendModules options type; }; };
        });
    };

    # Replacement for `attrsOf (submodule modules)` that:
    # - allows attributes to be `mkForce`d to `null` to "undefine" them
    # - can `coerce` shorthand attribute assignments to submodule definitions
    # - allows to define common config for all attributes by setting a module function
    # - adds `._module.{options,...}` metadata to each attribute for debugging / introspection (on the individual attribute instances)
    # The common-config-via-function is useful when all the attribute names are either not known or accessing them would cause a (infinite) recursion.
    # Currently, such "apply to all" definitions can only be defined by extending the `options` definition, which is unintuitive, verbose, and moves `config` where it does not belong.
    # TODO(PR): I really think this is strictly superior to `attrsOf submodule`. Search for /attrsOf [(]((lib[.])?types[.])?submodule/ (140 matches in nixpkgs)
    # One _could_ patch `attrsOf` to recognize when its `elemType` is a `submodule` instance and apply this logic there.
    types.attrsOfSubmodules = modulesOrArgs: (let
        args = if lib.isAttrs modulesOrArgs then modulesOrArgs else { modules = modulesOrArgs; what = 0; };
        modules = args.modules; coerce = args.coerce or { };
        submoduleType = types.addArgsToSubmodule (lib.types.submodule modules);
        elemType = lib.types.nullOr (if coerce == { } then submoduleType else lib.types.coercedTo coerce.from coerce.by submoduleType);
        attrsType = lib.types.attrsWith { elemType = elemType; lazy = false; };

        # for each attrset definition, applies its location information to all defined attributes
        pushPositions = map (def: lib.mapAttrs (n: v: { inherit (def) file; value = v; }) def.value);

        # this used to be in lib.types:
        checkDefsForError = check: loc: defs: let invalidDefs = lib.filter (def: !check def.value) defs; in if invalidDefs != [ ] then { message = "Definition values: ${lib.options.showDefs invalidDefs}"; } else null;

    in lib.types.mkOptionType rec {
        name = "attrsOfSubmodules";
        description = "either attribute set of (null${if coerce == { } then " or shorthand" else ""} or submodules) or submodule applying to all attributes";
        descriptionClass = "composite";
        check = { __functor = _: x: lib.isFunction x || attrsType.check x; isV2MergeCoherent = true; };
        merge = mkMergeV2Compat ({ loc, defs }: let
            applyToAll = lib.partition (def: lib.isFunction def.value) defs;
            evals = lib.filterAttrs (n: v: v.optionalValue.value or null != null) (
                lib.zipAttrsWith (name: defs: lib.modules.mergeDefinitions (loc ++ [ name ]) elemType (defs ++ (
                    lib.optionals (lib.all (_:_.value != null) defs) applyToAll.right # if any value is null, they either all are (and this attribute is to be ignored), or its an error
                ))) (pushPositions applyToAll.wrong)
            );
        in {
            headError = checkDefsForError check loc defs;
            value = lib.mapAttrs (n: v: v.optionalValue.value) evals; # 25.11 onwards: `// (let inherit (v.checkedAndMerged.valueMeta) configuration; in { _module = configuration._module // { _type = "moduleMeta"; inherit (configuration) extendModules options type; }; }`
            valueMeta.attrs = lib.mapAttrs (n: v: v.checkedAndMerged.valueMeta) evals;
        });
        functor = {
            inherit name; wrapped = null;
            type = types.attrsOfSubmodules;
            payload = args;
            binOp = lhs: rhs: {
                modules = lib.toList lhs.modules ++ lib.toList rhs.modules;
                coerce = if (lhs.coerce or { } != { }) && (lhs.coerce or { } != { }) && lhs.coerce != rhs.coerce then (
                    throw "A attrsOfSubmodules option is declared multiple times with conflicting coerce parameters."
                ) else if lhs.coerce or { } != { } then lhs.coerce else rhs.coerce or { };
            };
        };
        emptyValue.value = { };
        getSubOptions = prefix: elemType.getSubOptions (prefix ++ [ "<name>" ]);
        getSubModules = elemType.getSubModules;
        substSubModules = modules: types.attrsOfSubmodules { inherit modules coerce; };
        nestedTypes.elemType = elemType;
    });

}
