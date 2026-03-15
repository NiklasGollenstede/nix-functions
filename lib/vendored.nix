dirname: inputs@{ ...}: let
    inherit (inputs.nixpkgs) lib;
    inherit (lib) throwIfNot isAttrs mkMerge removeAttrs attrNames head;
in {

  # Verbatim from <nixpkgs>/lib/modules.nix, only accessible without the added deprecation warning:

  /**
    Massage a module into canonical form, that is, a set consisting
    of ‘options’, ‘config’ and ‘imports’ attributes.

    # Inputs

    `file`

    : 1\. Function argument

    `key`

    : 2\. Function argument

    `m`

    : 3\. Function argument
  */
  unifyModuleSyntax =
    file: key: m:
    let
      addMeta =
        config:
        if m ? meta then
          mkMerge [
            config
            { meta = m.meta; }
          ]
        else
          config;
      addFreeformType =
        config:
        if m ? freeformType then
          mkMerge [
            config
            { _module.freeformType = m.freeformType; }
          ]
        else
          config;
    in
    if m ? config || m ? options then
      let
        badAttrs = removeAttrs m [
          "_class"
          "_file"
          "key"
          "disabledModules"
          "imports"
          "options"
          "config"
          "meta"
          "freeformType"
        ];
      in
      if badAttrs != { } then
        throw "Module `${key}' has an unsupported attribute `${head (attrNames badAttrs)}'. This is caused by introducing a top-level `config' or `options' attribute. Add configuration attributes immediately on the top level instead, or move all of them (namely: ${toString (attrNames badAttrs)}) into the explicit `config' attribute."
      else
        {
          _file = toString m._file or file;
          _class = m._class or null;
          key = toString m.key or key;
          disabledModules = m.disabledModules or [ ];
          imports = m.imports or [ ];
          options = m.options or { };
          config = addFreeformType (addMeta (m.config or { }));
        }
    else
      # shorthand syntax
      throwIfNot (isAttrs m) "module ${file} (${key}) does not look like a module." {
        _file = toString m._file or file;
        _class = m._class or null;
        key = toString m.key or key;
        disabledModules = m.disabledModules or [ ];
        imports = m.require or [ ] ++ m.imports or [ ];
        options = { };
        config = addFreeformType (
          removeAttrs m [
            "_class"
            "_file"
            "key"
            "disabledModules"
            "require"
            "imports"
            "freeformType"
          ]
        );
      };

}
