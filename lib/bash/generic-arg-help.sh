## Shows the help text for a program and exits, if »--help« was passed as argument and parsed, or does nothing otherwise.
#  Expects to be called between parsing and verifying the arguments.
#  Uses »allowedArgs« for the list of the named arguments (the values are the descriptions).
#  »name« should be the program name/path (usually »$0«), »args« the form/names of any positional arguments expected (e.g. »SOURCE... DEST«) and is included in the "Usage" description,
#  »description« the introductory text shown before the "Usage", and »suffix« any text printed after the argument list.
#  This function requires »sort« (from coreutils) on the PATH.
function generic-arg-help { # 1: name, 2?: args, 3?: description, 4?: suffix, 5?: usageLine
    if [[ ! ${args[help]:-} ]] ; then : ${allowedArgs[help]:=1} ; \return 0 ; fi
    [[ ! ${3:-} ]] || echo "$3"
    printf "${5:-Usage:\n    %s [FLAG[=value]]... [--] %s\n\nWhere »FLAG« may be any of:\n}" "$1" "${2:-}"
    local name ; while IFS= read -u3 -r name ; do
        printf '    %s\n        %s\n' "$name" "${allowedArgs[$name]//$'\n'/$'\n        '}"
    done 3< <( printf '%s\n' "${!allowedArgs[@]}" | LC_ALL=C sort )
    printf '    %s\n        %s\n' "--help" "Do nothing but print this message and exit with success."
    [[ ! ${4:-} ]] || echo "$4"
    \exit 0
}
