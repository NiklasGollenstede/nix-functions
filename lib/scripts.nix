dirname: inputs@{ self, nixpkgs, ...}: let
    inherit (nixpkgs) lib;
    inherit (import "${dirname}/vars.nix" dirname inputs) extractLineAnchored;
in rec {

    # Turns an attr set into a bash dictionary (associative array) declaration, e.g.:
    # bashSnippet = "declare -A dict=(\n${asBashDict { } { foo = "42"; bar = "baz"; }})"
    asBashDict = { mkName ? (n: v: n), mkValue ? (n: v: v), indent ? "    ", ... }: attrs: (
        builtins.concatStringsSep "" (lib.mapAttrsToList (name: value: (
            let key = mkName name value; in if key == null then "" else
            "${indent}[${lib.escapeShellArg key}]=${lib.escapeShellArg (mkValue name value)}\n"
        )) attrs)
    );

    # This function allows using nix values in bash scripts, without the need to pass an explicit and manually curated list of values to the script:
    # Given a path list of bash script »sources« and an attrset »context«, this function parses the scripts for the literal sequence »@{« followed by a lookup path of period-joined words, and, for each match, resolves the attribute path against »context«, declares a variable with that value, and swaps out the »@{« plus path for a »${« use of the declared variable.
    # The returned script sources the variable definitions and all translated »sources« in order.
    #
    # The lookup path may end in »!« plus the name of a function and optionally string arguments separated by ».«s, in which case the function is taken from »helpers//inputs.self.lib//(pkgs.lib or lib)//pkgs//builtins« and called with the string args and the resolved value as last arg; the return value then replaces the resolved value.
    # Examples: »!attrNames«, »!toJSON«, »!catAttrs«, »!hashString.sha256«, »!writeText.filename«.
    #
    # The names of the declared values are the lookup paths, with ».«/»!«/»-« replaced by »_«/»1«/»0«.
    # The symbol immediately following the lookup path (/builtin name) can be »}« or any other symbol that bash variable substitutions allow after the variable name (like »:«, »/«), eliminating the need to assign to a local variable to do things like replacements, fallbacks or substrings.
    #
    # If the lookup path does not exist in »context«, then the value will be considered the same as »null«, and a value of »null« will result in a bash variable that is not defined (which can then be handled in the bash script).
    # Other scalars (bool, float, int, path) will be passed to »builtins.toString«. Anything that has an ».outPath« that is a string will be passed as that ».outPath«.
    #
    # Lists will be declared as bash arrays, attribute sets will be declared as associative arrays using »asBashDict«.
    # Bash does not support any nested data structures. Lists or attrsets within lists or attrsets are therefore (recursively) encoded and escaped as strings, such that calling »eval« on them is safe if (but only if) they are known to be encoded from nested lists/attrsets. Example: »eval 'declare -A fs='"@{config.fileSystems['/']}" ; root=${fs[device]}«.
    #
    # Any other value type (functions), and things that »builtins.toString« doesn't like, or things that fail to evaluate, will throw here.
    #
    # This function returns an attribute set that can be cast to a (script) string, for the full effect described above, but additionally exposes the following attributes:
    # * »decls«: deduplicated list of the lookup paths (as verbatim strings) of all encountered »@{« substitutions,
    # * »vars«: attribute set mapping each »decls« entry to its resolved value,
    # * »bash-ify«: function with arguments »decl« and »value« that creates a bash variable declaration (with value assignment),
    # * »scripts«: the processed scripts sourced by main script returned.
    substituteImplicit = args@{
        scripts, # List of paths to scripts to process and then source in the returned script. Each script may also be an attrset »{ name; text; }« instead of a path.
        context, # The root attrset for the resolution of substitutions.
        pkgs, # Instantiated »nixpkgs«, as fallback location for helpers, and to grab »writeScript« etc from.
        helpers ? { }, # Attrset of (highest priority) helper functions.
        trace ? (m: v: v), # Function that gets called with the names and values as they are processed. Pass »builtins.trace« for debugging, esp. when evaluating one of the accessed values fails.
    }: let
        parsedScripts = map (source: rec {
            text = if builtins.isAttrs source then source.text else builtins.readFile source; name = if builtins.isAttrs source then source.name else builtins.baseNameOf source;
            parsed = builtins.split ''@\{([#!]?)([a-zA-Z][a-zA-Z0-9_.-]*[a-zA-Z0-9](![a-zA-Z][a-zA-Z0-9_.-]*[a-zA-Z0-9])?)([:*@\[#%/^,\}])'' text; # (first part of a bash parameter expansion, with »@« instead of »$«)
        }) args.scripts;
        decls = lib.unique (map (match: builtins.elemAt match 1) (builtins.filter builtins.isList (builtins.concatMap (script: script.parsed) parsedScripts)));
        vars = builtins.listToAttrs (map (decl: let
            call = let split = builtins.split "!" decl; in if (builtins.length split) == 1 then null else builtins.elemAt split 2;
            path = (builtins.filter builtins.isString (builtins.split "[.]" (if call == null then decl else builtins.substring 0 ((builtins.stringLength decl) - (builtins.stringLength call) - 1) decl)));
            resolved = lib.attrByPath path null context;
            applied = if call == null || resolved == null then resolved else (let
                split = builtins.filter builtins.isString (builtins.split "[.]" call); name = builtins.head split; args = builtins.tail split;
                func = builtins.foldl' (func: arg: func arg) (helpers.${name} or self.lib.${name} or (pkgs.lib or lib).${name} or pkgs.${name} or builtins.${name}) args;
            in func resolved);
        in { name = decl; value = applied; }) decls);
        bash-ify = decl: applied: let
            value = if builtins.isString (applied.outPath or null) then applied.outPath else if (
                (builtins.isBool applied) || (builtins.isFloat applied) || (builtins.isInt applied) || (builtins.isPath applied)
            ) then builtins.toString applied else applied;
            name = trace "substituteImplicit »${decl}« =>" (builtins.replaceStrings [ "." "!" "-" ] [ "_" "1" "0" ] decl);
            toStringRecursive = value: if builtins.isString (value.outPath or null) then (
                value.outPath
            ) else if builtins.isAttrs value then (
                "(\n${asBashDict { mkName = name: value: if value == null then null else name; mkValue = name: toStringRecursive; } value})"
            ) else if (builtins.isList value) then (
                "( ${lib.escapeShellArgs (map toStringRecursive value)} )"
            ) else (toString value);
        in (let final = (
                 if (value == null) then "#${name}=null"
            else if (builtins.isString value) then "${name}=${lib.escapeShellArg value}"
            else if (builtins.isList value) then "${name}=${toStringRecursive value}"
            else if (builtins.isAttrs value) then "declare -A ${name}=${toStringRecursive value}"
            else throw "Can't use value of unsupported type ${builtins.typeOf} as substitution for ${decl}" # builtins.isFunction
        ); in trace final final);
        declarations = pkgs.writeText "vars" ("#!/usr/bin/env bash\n" + (builtins.concatStringsSep "\n" (lib.mapAttrsToList (bash-ify) vars)));
        processedScripts = map (script: pkgs.writeScript script.name (
            builtins.concatStringsSep "" (map (seg: if builtins.isString seg then seg else (
                "$"+"{"+(builtins.head seg)+(builtins.replaceStrings [ "." "!" "-" ] [ "_" "1" "0" ] (builtins.elemAt seg 1))+(toString (builtins.elemAt seg 3))
            )) script.parsed)
        )) parsedScripts;
        script = ''
            source ${declarations}
            ${builtins.concatStringsSep "\n" (map (script: "source ${script}") processedScripts)}
        '';
    in { __toString = _: script; inherit script decls vars bash-ify; scripts = [ declarations ] ++ processedScripts; };

    ## Given a bash »script« as string and a function »name«, this finds and extracts the definition of that function in and from the script.
    #  The function definition has to start at the beginning of a line and must end on the next line that is a sole »}« or »)}«.
    extractBashFunction = script: name: let
        inherit (extractLineAnchored ''${name}[ ]*[(][ ]*[)]|function[ ]+${name}[ ]'' true false script) line after;
        #inherit (extractLineAnchored ''${name}[ ]*[(][ ]*[)]|function[ ]+${name}[^A-Za-z0-9_-]?[^\n]*'' true true script) line after;
        body = builtins.split "(\n[)]?[}])[ ]*([#][^\n]*)?\n" after;
    in if (builtins.length body) < 3 then null else line + (builtins.head body) + (builtins.head (builtins.elemAt body 1));

    # Used as a »system.activationScripts« snippet, this performs substitutions on a »text« before writing it to »path«.
    # For each name-value pair in »substitutes«, all verbatim occurrences of the attribute name in »text« are replaced by the content of the file with path of the attribute value.
    # Since this happens one by one in no defined order, the attribute values should be chosen such that they don't appear in any of the files that are substituted in.
    # If a file that is supposed to be substituted in is missing, then »placeholder« is inserted instead, and the activation snipped reports a failure.
    # If »enable« is false, then the file at »path« is »rm«ed instead.
    writeSubstitutedFile = { enable ? true, path, text, substitutes, placeholder ? "", perms ? "440", owner ? "root", group ? "root", }: let
        hash = builtins.hashString "sha256" text;
        esc = lib.escapeShellArg;
    in { "write ${path}" = if enable then ''
        text=$(cat << '#${hash}'
        ${text}
        #${hash}
        )
        ${builtins.concatStringsSep "\n" (lib.mapAttrsToList (name: file: "text=\"\${text//${esc name}/$( if ! cat ${esc file} ; then printf %s ${esc placeholder} ; false ; fi )}\"") substitutes)}
        install -m ${esc (toString perms)} -o ${esc (toString owner)} -g ${esc (toString group)} /dev/null ${esc path}
        <<<"$text" cat >${esc path}
    '' else ''rm ${esc path} || true''; };

    # Wraps a (bash) script into a "package", making »deps« available on the script's path.
    wrap-script = args@{ pkgs, src, deps, ... }: let
        name = args.name or (builtins.baseNameOf (builtins.unsafeDiscardStringContext "${src}"));
    in pkgs.runCommandLocal name {
        script = src; nativeBuildInputs = [ pkgs.buildPackages.makeWrapper ];
    } ''makeWrapper $script $out/bin/${name} --prefix PATH : ${lib.makeBinPath deps}'';

}
