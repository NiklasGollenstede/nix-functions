dirname: inputs: let
    inherit (inputs.nixpkgs.sourceInfo.unpatched or inputs.nixpkgs) lib;
    inherit (import "${dirname}/vars.nix" dirname inputs) extractLineAnchored withOverride;
    inherit (import "${dirname}/misc.nix" dirname inputs) ifNull;
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
    substituteImplicit = lib.makeOverridable (args@{
        scripts, # List of scripts to process and then source in the returned script. Each script may be an attrset »{ name; text; }« or as a path that is expanded via »builtins.baseNameOf« and »builtins.readFile«. Each script must have a unique »name« (either explicitly of the path's basename).
        context, # The root attrset for the resolution of substitutions.
        pkgs, # Instantiated »nixpkgs«, as fallback location for helpers, and to grab »writeScript« etc from.
        helpers ? { }, # Attrset of (highest priority) helper functions.
        onError ? "exit", # Bash command to run when sourcing any of the scripts failed.
        trace ? (m: v: v), # Function that gets called with the names and values as they are processed. Pass »builtins.trace« for debugging, esp. when evaluating one of the accessed values fails.
        mapValue ? (v: v), # Function that gets called on each value (recursively) directly before is is stringified to be included in the output script.
    }: let
        parsedScripts = map (source: rec {
            text = if builtins.isAttrs source then source.text else builtins.readFile source;
            name = if builtins.isAttrs source then source.name else builtins.baseNameOf source;
            parsed = builtins.split ''@\{([#!]?)([a-zA-Z][a-zA-Z0-9_.-]*[a-zA-Z0-9](![a-zA-Z][a-zA-Z0-9_.-]*[a-zA-Z0-9])?)([:*@\[#%/^,\}])'' text; # (first part of a bash parameter expansion, with »@« instead of »$«)
            processed = builtins.concatStringsSep "" (map (seg: if builtins.isString seg then seg else (
                "$"+"{"+(builtins.head seg)+(builtins.replaceStrings [ "." "!" "-" ] [ "_" "1" "0" ] (builtins.elemAt seg 1))+(toString (builtins.elemAt seg 3))
            )) parsed);
        }) args.scripts;
        decls = lib.unique (map (match: builtins.elemAt match 1) (builtins.filter builtins.isList (builtins.concatMap (script: script.parsed) parsedScripts)));
        vars = builtins.listToAttrs (map (decl: let
            call = let split = builtins.split "!" decl; in if (builtins.length split) == 1 then null else builtins.elemAt split 2;
            path = (builtins.filter builtins.isString (builtins.split "[.]" (if call == null then decl else builtins.substring 0 ((builtins.stringLength decl) - (builtins.stringLength call) - 1) decl)));
            resolved = lib.attrByPath path null context;
            applied = if call == null || resolved == null then resolved else (let
                split = builtins.filter builtins.isString (builtins.split "[.]" call); name = builtins.head split; args = builtins.tail split;
                func = builtins.foldl' (func: arg: func arg) (helpers.${name} or inputs.self.lib.${name} or (pkgs.lib or inputs.nixpkgs.lib).${name} or pkgs.${name} or builtins.${name}) args;
            in func resolved);
        in { name = decl; value = applied; }) decls);
        bash-ify = decl: applied: let
            value = mapValue (if builtins.isString (applied.outPath or null) then applied.outPath else if (
                (builtins.isBool applied) || (builtins.isFloat applied) || (builtins.isInt applied) || (builtins.isPath applied)
            ) then builtins.toString applied else applied);
            name = trace "substituteImplicit »${decl}« =>" (builtins.replaceStrings [ "." "!" "-" ] [ "_" "1" "0" ] decl);
            toStringRecursive = value: if builtins.isString (value.outPath or null) then (
                value.outPath
            ) else if builtins.isAttrs value then (
                "(\n${asBashDict { mkName = name: value: if (mapValue value) == null then null else name; mkValue = name: value: toStringRecursive (mapValue value); } value})"
            ) else if (builtins.isList value) then (
                "( ${lib.escapeShellArgs (map (value: toStringRecursive (mapValue value)) value)} )"
            ) else (toString value);
        in (let final = (
                 if (value == null) then "#${name}=null"
            else if (builtins.isString value) then "${name}=${lib.escapeShellArg value}"
            else if (builtins.isList value) then "${name}=${toStringRecursive value}"
            else if (builtins.isAttrs value) then "declare -A ${name}=${toStringRecursive value}"
            else throw "Can't use value of unsupported type ${builtins.typeOf} as substitution for ${decl}" # builtins.isFunction
        ); in trace final final);
        scriptsDir = writeTextFiles pkgs "scripts" { executable = "*"; } scriptFiles;
        scriptFiles = (
            (builtins.listToAttrs (map (script: { name = builtins.unsafeDiscardStringContext script.name; value = script.processed; }) parsedScripts)
        ) // {
            __vars__ = builtins.concatStringsSep "\n" (lib.mapAttrsToList (bash-ify) vars);
            __main__ = builtins.concatStringsSep "\n" ([ "source ${placeholder "out"}/__vars__ || ${onError}" ] ++ (map (script: "source ${placeholder "out"}/${script.name} || ${onError}") parsedScripts));
        });
        script = "source ${scriptsDir}/__main__ || ${onError}";
        #script = builtins.concatStringsSep "\n" ([ "source ${scriptsDir}/__vars__ || ${onError}" ] ++ (map (script: "source ${scriptsDir}/${script.name} || ${onError}") parsedScripts));
    in {
        # A Bash snippet that can be included in a script file to execute the transformed input scripts.
        inherit script;
        # For backwards compatibility.
        __toString = _: script;
        # List of each requested lookup path, as found in the input scripts.
        inherit decls;
        # Attribute set mapping each decl to its resolved value.
        inherit vars;
        # Function that turns a decl and its resolved value into a bash variable declaration.
        inherit bash-ify;
        # Text contents of the processed scripts, as attr set of their »name«s. »__vars__« contains the generated variable declarations, and »__main__« contains a snippet that imports the rest in the correct order.
        inherit scriptFiles;
        # The processed scripts written to a single output directory.
        inherit scriptsDir;
        # List of all produced files. Sorted.
        scripts = [ "${scriptsDir}/__vars__" ] ++ (map ({ name, ... }: "${scriptsDir}/${name}") parsedScripts) ++ [ "${scriptsDir}/__main__" ];
    });

    ## Given a bash »script« as string and a function »name«, this finds and extracts the definition of that function in and from the script.
    #  The function definition has to start at the beginning of a line and must end on the next line that is a sole »}« or »)}«.
    extractBashFunction = script: name: let
        inherit (ifNull (extractLineAnchored ''${name}[ ]*[(][ ]*[)]|function[ ]+${name}[ ]'' true false script) (throw "can't find bash function »${name}«")) line after;
        #inherit (extractLineAnchored ''${name}[ ]*[(][ ]*[)]|function[ ]+${name}[^A-Za-z0-9_-]?[^\n]*'' true true script) line after;
        body = builtins.split "(\n[)]?[}])[ ]*([#][^\n]*)?\n" after;
    in if (builtins.length body) < 3 then null else line + (builtins.head body) + (builtins.head (builtins.elemAt body 1));

    ## Converts a (flat) attribute set of "files" (text & symlink) into a file tree.
    writeTextFiles = pkgs: name: args@{
        destination ? "", # Relative path appended to $out (and cwd). Example: "bin". Default: "".
        executable ? "",  # Optional shell globs of paths to run »chmod +x« on. Example: "bin/* lib/foo/*.so". Default: all files directly in bin/.
        checkPhase ? "",  # Shell code to check the written files, executed in `destination`. Example: ''for f in "''${fileNames[@]}" ; do ${stdenv.shellDryRun} "$f" ; done''. Default: `shellDryRun` on all files in bin/ whose text starts with `#!...(ba)?sh...` or whose source path ends in `.sh`. (TODO?: do the check in bash and always check the file contents?)
    ... }: files: let     # { ${path} = ( string | { text = string; } | { source = string; } ); }
        contents = builtins.attrValues files;
        numbered = builtins.genList (i: let c = builtins.elemAt contents i; text = if builtins.isString c then c else if c?text && builtins.isString c.text then c.text else null; in rec { symlink = text == null; name = "${if symlink then "link" else "text"}_${toString i}"; value = if symlink then c.source else text; }) (builtins.length contents);
        partitioned = builtins.partition (_:_.symlink) numbered; passAsFiles = builtins.listToAttrs partitioned.wrong; passAsVars = builtins.listToAttrs partitioned.right;
        ctnBin = lib.count (lib.hasPrefix "bin/") (builtins.attrNames files); hasBin = ctnBin > 0;
        isShellScript = file: if file?source then lib.hasSuffix ".sh" "${file.source}" else (builtins.match ''^#![^${"\n"}]{1,128}[ \/](ba)?sh[${"\n"} ].*'' (file.text or file)) != null;
        #mainProgPath = if args.passthru?mainProgram then if destination == "bin" then args.passthru.mainProgram else if destination == "" then "bin/${args.passthru.mainProgram}" else "" else "";
    in pkgs.runCommandLocal name (args // passAsFiles // passAsVars // {
        fileNames = builtins.concatStringsSep "\n" (builtins.attrNames files); passAsFile = [ "fileNames" ] ++ builtins.attrNames passAsFiles;
        passthru = (args.passthru or { }) // { inherit files; };
        meta = if destination == "" && ctnBin == 1 then { mainProgram = lib.removePrefix "bin/" (lib.findFirst (lib.hasPrefix "bin/") null (builtins.attrNames files)); } // (args.meta or { }) else args.meta or { };
        executable = args.executable or (if destination == "bin" then "*" else if hasBin then  "bin/*" else null);
        #executable = args.executable or (lib.escapeShellArg mainProgPath);
        checkPhase = args.checkPhase or (if args?executable then "" else builtins.concatStringsSep "" (lib.mapAttrsToList (name: value: if (destination == "bin" || lib.hasPrefix "bin/" name) && (isShellScript value) then "${pkgs.stdenv.shellDryRun} ${lib.escapeShellArg name}\n" else "") files));
    }) '' # bash
        mkdir -p $out ; cd $out
        if [[ $destination ]] ; then mkdir -p "''${destination#/}" ; cd "''${destination#/}" ; fi

        readarray -t fileNames <$fileNamesPath
        index=0 ; for name in "''${fileNames[@]}" ; do
            mkdir -p "$( dirname "$name" )"
            declare link=link_$(( index ))
            if [[ ''${!link:-} ]] ; then
                ln -sT "''${!link}" "$name"
            else
                declare text=text_$(( index ))Path
                mv "''${!text}" "$name"
            fi
            : $(( index++ ))
        done

        if [[ "$executable" ]]; then chmod +x -- $executable ; fi
        cd $out ; eval "$checkPhase"
    '';

    # Used as a bash script snippet, this performs substitutions on a »text« before writing it to »path«.
    # For each name-value pair in »substitutes«, all verbatim occurrences of the attribute name in »text« are replaced by the content of the file with path of the attribute value.
    # Since this happens one by one in no defined order, the attribute values should be chosen such that they don't appear in any of the files that are substituted in.
    # If a file that is supposed to be substituted in is missing, then »placeholder« is inserted instead, the other substitutions and writing of the file continues, but the snippet returns a failure exit code.
    writeSubstitutedFile = { path, text, substitutes, placeholder ? "", owner ? "root", group ? "root", mode ? "440", }: let
        hash = builtins.hashString "sha256" text;
        esc = lib.escapeShellArg;
    in "(${''
        text=$(cat << ${"'#${hash}'\n${text}\n#${hash}\n"})
        placeholder=${esc placeholder}
        failed= ; ${builtins.concatStringsSep "\n" (lib.mapAttrsToList (ref: file: ''
            subst=$( if ! cat ${esc file} ; then printf %s "$placeholder" ; false ; fi ) || failed=1
            text=''${text//${esc ref}/$subst}
        '') substitutes)}
        <<<"$text" install /dev/stdin -m ${esc (toString mode)} -o ${esc (toString owner)} -g ${esc (toString group)} ${esc path}
        if [[ $failed ]] ; then false ; fi
    ''})";


    # `nix print-dev-env $drv`, as a normal derivation producing a sourceable script, instead of a function baked into nix.
    # For derivations with structured attrs, the generated script (re-)creates the files NIX_ATTRS_SH_FILE and NIX_ATTRS_JSON_FILE when sourced, in NIX_BUILD_TOP (or a new temporary directory, if »!newTmp«). Unlike `nix print-dev-env` (which writes them to a directory that it deletes before the script can be sourced), their contents get their output paths rewritten as well.
    print-dev-env = withOverride ({
        drv, # The derivation to generate the env script for.
        newTmp ? true, # Whether to point NIX_BUILD_TOP and TMP/TMPDIR/TEMP/TEMPDIR to a new temporary directory (as `nix develop`/`nix print-dev-env` does), or leave them untouched.
        outputsDir ? "outputs", # The directory prefix to which output paths are rewritten (»/nix/store/...« -> »$PWD/<outputsDir>/<outputName>«, everywhere in the generated script), or »null« to leave them untouched. The path is prefixed with »$PWD« if not absolute and, as with `nix print-dev-env`, used as verbatim replacement (so you probably don't want special characters or spaces in it (or PWD)).
        prePrint ? "", postPrint ? "", # Optional shell code to run in the builder before and after printing the generated environment script to stdout.
    }: override: let
        marker = name: "__NIX_${name}_\${__nix_dev_env_main##*/}__"; # (bash) heredoc end markers, unique to (and deterministic for) the derivation
        # these were taken from: <nix>/src/nix/develop.cc
        ignoreVars = [ "BASHOPTS" "HOME" "NIX_BUILD_TOP" "NIX_ENFORCE_PURITY" "NIX_LOG_FD" "NIX_REMOTE" "PPID" "SHELLOPTS" "SSL_CERT_FILE" "TEMP" "TEMPDIR" "TERM" "TMP" "TMPDIR" "TZ" "UID" ];
        savedVars = [ "PATH" "XDG_DATA_DIRS" ];
        randomSeedPath = if drv ? out then builtins.unsafeDiscardStringContext drv.out.outPath else "";
    in lib.flip builtins.removeAttrs [
        "overrideAttrs" "overrideDerivation" # to override derivation properties, use »env.override (old: { drv = old.drv.overrideAttrs ...; })«
    ] ((drv.overrideAttrs (finalAttrs: prevAttrs: {
        name = "${drv.name}-env"; # (like `nix develop`) to distinguish the store paths from the actual package, Original name is restored below.
        builder = drv.stdenv.shell; # This should already be the case for any standard derivation (nix develop throws before building if not), and using "args" to replace the build command is the least invasive way to pass them, as "args" are not in the environment.
        # The outputs have to stay as they are (for their variables in the env and for »builtins.placeholder« to work). Since the declared `outputs` are not the whole truth (e.g., `separateDebugInfo` adds `debug`) and may be changed by later overrides, the builder takes them from its environment and `touch`es all of them.

        # Remove output checks (like `nix develop` does), as the generated script references everything. `overrideAttrs` can't remove attributes, so set them to values that disable the checks (`mkDerivation` maps `null`s in `allowed*` through, which then get ignored).
        ${if prevAttrs ? allowedReferences then "allowedReferences" else null} = null;
        ${if prevAttrs ? allowedRequisites then "allowedRequisites" else null} = null;
        ${if prevAttrs ? disallowedReferences then "disallowedReferences" else null} = [ ];
        ${if prevAttrs ? disallowedRequisites then "disallowedRequisites" else null} = [ ];
        ${if prevAttrs ? outputChecks then "outputChecks" else null} = { };
        args = [ "-c" '' # bash
            if [[ -e "$NIX_ATTRS_SH_FILE" ]]; then source "$NIX_ATTRS_SH_FILE"; fi
            # map of all output names to their paths (variables prefixed with »__nix_dev_env_« are excluded from the generated script)
            declare -A __nix_dev_env_outputs=( )
            if [[ -e "$NIX_ATTRS_SH_FILE" ]] ; then
                for __nix_dev_env_o in "''${!outputs[@]}" ; do __nix_dev_env_outputs[$__nix_dev_env_o]=''${outputs[$__nix_dev_env_o]} ; done
            else
                for __nix_dev_env_o in $outputs ; do __nix_dev_env_outputs[$__nix_dev_env_o]=''${!__nix_dev_env_o} ; done
            fi
            for __nix_dev_env_o in "''${__nix_dev_env_outputs[@]}" ; do : >>"$__nix_dev_env_o" || exit ; done
            __nix_dev_env_main=''${__nix_dev_env_outputs[${builtins.head (finalAttrs.outputs or [ "out" ])}]:-} # first/default output
            unset __nix_dev_env_o
            exec {__nix_dev_env_stdout}>&1 >>"$__nix_dev_env_main" || exit # redirect stdout, but save the original
            ${lib.optionalString (outputsDir != null) ''
                # read the rest of the script into a variable (see the end of the script)
                echo "IFS= read -r -d \"\" __nix_print_dev_env <<'${marker "PRINT_DEV_ENV"}' || :"
            ''}
            export IN_NIX_SHELL=impure ; export dontAddDisableDepTrack=1
            if [[ -n $stdenv ]]; then
                export NIX_OUTPATH_USED_AS_RANDOM_SEED=${lib.escapeShellArg randomSeedPath} # use the same »-frandom-seed« as the real build
                set -e ; source "$stdenv"/setup >&$__nix_dev_env_stdout ; set +e
                unset NIX_OUTPATH_USED_AS_RANDOM_SEED
            fi
            name=${lib.escapeShellArg drv.name} # restore the original name

            ${prePrint}
            echo 'unset shellHook'
            ${lib.concatStrings (map (var: ''
                echo '${var}=''${${var}:-} ; nix_saved_${var}="''$${var}"'
            '') savedVars)} # bash
            declare -p | while IFS="" read -r line ; do
                # from <nix>/src/nix/get-env.sh:
                if ! [[ $line =~ ^declare\ (-[^ ])\ ([^=]*) ]] ; then continue ; fi
                type=''${BASH_REMATCH[1]} ; name=''${BASH_REMATCH[2]}
                if [[ ' -x -- -a -A ' != *' '$type' '* ]] ; then continue; fi
                if [[ $name =~ ^BASH_ || $name =~ ^COMP_ || ' _ DIRSTACK EUID FUNCNAME HISTCMD HOSTNAME GROUPS PIPESTATUS PWD RANDOM SHLVL SECONDS EPOCHREALTIME EPOCHSECONDS ' == *' '$name' '* ]] ; then continue; fi
                # end from <nix>/src/nix/get-env.sh
                if [[ $name == __nix_dev_env_* || ' ${lib.concatStringsSep " " ignoreVars} BASH HOSTTYPE IFS LINENO MACHTYPE OLDPWD OPTERR OSTYPE PS4 SHELL ' == *' '$name' '* ]] ; then continue; fi
                if [[ ( $type == -a || $type == -A ) && $line != *=* ]] ; then line+='=()' ; fi # declared-only arrays as empty arrays (like `nix print-dev-env`)
                printf 'declare -g %s\n' "''${line#declare }" # global, even if the script is sourced from within a function
            done
            declare -F | while IFS="" read -r line ; do
                if ! [[ $line =~ ^declare\ -f\ ([^ ]+) ]] ; then continue ; fi
                declare -f "''${BASH_REMATCH[1]}"
            done
            ${lib.concatStrings (map (var: ''
                echo '${var}="''$${var}''${nix_saved_${var}:+:$nix_saved_${var}}"'
            '') savedVars)}
            ${lib.optionalString newTmp ''
                echo 'export NIX_BUILD_TOP="$( mktemp -d -t nix-shell.XXXXXX )"'
                ${lib.concatStrings (map (var: ''
                    echo 'export ${var}="$NIX_BUILD_TOP"'
                '') [ "TMP" "TMPDIR" "TEMP" "TEMPDIR" ])}
            ''}
            if [[ -e "$NIX_ATTRS_SH_FILE" ]] ; then
                # embed the structured-attrs files, to be written (and pointed to) when sourced
                echo '${if newTmp then ''export NIX_ATTRS_SH_FILE="$NIX_BUILD_TOP/.attrs.sh"'' else ''export NIX_ATTRS_SH_FILE="$( mktemp -d -t nix-attrs.XXXXXX )/.attrs.sh"''}'
                echo 'export NIX_ATTRS_JSON_FILE="''${NIX_ATTRS_SH_FILE%/*}/.attrs.json"'
                ${lib.concatMapStrings (ext: let
                    nameInAttrs = { SH = name: "declare name='${name}'"; JSON = name: ''"name":"${name}"''; };
                in ''
                    echo "IFS= read -r -d \"\" __nix_dev_env_attrs <<'${marker "ATTRS_${ext}"}' || :"
                    __nix_dev_env_attrs=$(<"$NIX_ATTRS_${ext}_FILE")
                    __nix_dev_env_from=${lib.escapeShellArg (nameInAttrs.${ext} "${drv.name}-env")} ; __nix_dev_env_to=${lib.escapeShellArg (nameInAttrs.${ext} drv.name)}
                    __nix_dev_env_attrs=''${__nix_dev_env_attrs/"$__nix_dev_env_from"/"$__nix_dev_env_to"} # (restore the original name)
                    printf '%s\n' "$__nix_dev_env_attrs"
                    echo "${marker "ATTRS_${ext}"}"
                    echo 'printf %s "$__nix_dev_env_attrs" >"$NIX_ATTRS_${ext}_FILE" ; unset __nix_dev_env_attrs'
                '') [ "SH" "JSON" ]}
            fi
            echo 'eval "''${shellHook:-}"'
            ${postPrint}

            ${lib.optionalString (outputsDir != null) ''
                # end the heredoc, rewrite all occurrences of output paths in it to »outputsDir« (like <nix>/src/nix/develop.cc's »makeRcScript« does), and eval it (with the helper var already unset)
                echo "${marker "PRINT_DEV_ENV"}"
                for __nix_dev_env_o in "''${!__nix_dev_env_outputs[@]}" ; do
                    printf '__nix_print_dev_env=''${__nix_print_dev_env//"%s"/%s/%s}\n' "''${__nix_dev_env_outputs[$__nix_dev_env_o]}" ${lib.escapeShellArg (
                        (if lib.hasPrefix "/" outputsDir then "" else ''"$PWD"/'') + lib.escapeShellArg outputsDir
                    )} "$__nix_dev_env_o"
                done
                echo 'eval "unset __nix_print_dev_env ; $__nix_print_dev_env"'
            ''}
            # restore stdout, so that anything appended to the builder command (or exit hooks) doesn't write to the generated script
            exec >&$__nix_dev_env_stdout {__nix_dev_env_stdout}>&-
        '' ];
    })) // { inherit override; }));


    # Wraps a (bash) script into a "package", making »deps« available on the script's path.
    wrap-script = args@{ pkgs, src, deps, ... }: let
        name = args.name or (builtins.baseNameOf (builtins.unsafeDiscardStringContext "${src}"));
    in pkgs.runCommandLocal name {
        script = src; nativeBuildInputs = [ pkgs.buildPackages.makeWrapper ];
    } ''makeWrapper $script $out/bin/${name} --prefix PATH : ${lib.makeBinPath deps}'';

    # CDs the current shell to the closest parent directory that contains a marker file (path).
    intoDirWith = marker: ''
        while true ; do
            if [ -e ./${marker} ] ; then break ; fi # this should be a good indicator
            cd .. ; if [ $PWD = / ] ; then echo 'Unable to locate ${marker} in (parent of) CWD' >&2 ; exit ''${exitCodeOnError:-1} ; fi
        done
    '';
    # Wraps a snippet of shell code such that it is executed with its CWD set to the closest parent directory that contains a marker file.
    inDirWith = marker: shellCode: ''
        ( ${intoDirWith marker} {
            ${shellCode}
        } )
    '';
    # CDs the current shell to the closest parent directory that contains a ».git/config« file.
    intoRepoDir = intoDirWith ".git/config";
    # CDs the current shell to the closest parent directory that contains a »flake.nix« file.
    intoFlakeDir = intoDirWith "flake.nix";
    # Wraps a snippet of shell code such that it is executed with its CWD set to the closest parent directory that contains a ».git/config« file.
    inRepoDir = inDirWith ".git/config";
    # Wraps a snippet of shell code such that it is executed with its CWD set to the closest parent directory that contains a »flake.nix« file.
    inFlakeDir = inDirWith "flake.nix";

}
