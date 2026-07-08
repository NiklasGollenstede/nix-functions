## Shows the help text for a program and exits, if »--help« (or optionally »-h«/»-?«) was passed as argument and parsed, or does nothing otherwise.
#  This function expects to be called between parsing (»generic-arg-parse«) and verifying (»generic-arg-verify«) the arguments.
#  The decision to show the help text is based on the parsed arguments, and the named input variable »shortArgsAre« (with the same meaning/values as in »generic-arg-parse«).
#  The argument descriptions are taken from the names and values of the »allowedArgs« associative array as used by »generic-arg-verify«.
#  Additionally, the following optional positional arguments may be passed:
#  1 - »progName«: the program name/path (default: »$0«),
#  2 - »args«: the form/names of any positional arguments (e.g. »SOURCE... DEST«), which is included in the "Usage" description,
#  3 - »summary«: the introductory text shown before the "Usage",
#  4 - »details«: any text printed after the argument list, and
#  5 - »usageLineFmt«: a format string for the "Usage" line, which is passed to »printf« with »progName« and »args« as arguments.
#  This function uses »fmt« and »sort« (from coreutils) if available on $PATH.
function generic-arg-help { # 1?: progName, 2?: args, 3?: summary, 4?: details, 5?: usageLineFmt
    if [[ ! ${args[help]:-} && ! ( ${shortArgsAre:-} && ${shortArgsAre,,} == flags && ( ${shortArgs[h]:-} || ${shortArgs['?']:-} ) ) ]] ; then \return 0 ; fi
    local progName=${1:-$0} args=${2:-} summary=${3:-} details=${4:-}
    local usageLineFmt="${5:-Usage:\n    %s [OPTION[=value]]... [--] %s\n\nWhere »OPTION« may be any of:\n\n}"
    local columns= ; if [[ -t 1 ]] && type -t fmt &>/dev/null ; then
        [[ ${COLUMNS:-} =~ ^[0-9]+$ ]] && columns=$COLUMNS || columns=$( stty --file=/dev/stdout size ) &>/dev/null || columns=$( tput cols ) &>/dev/null || true ; columns=${columns##* }
    fi
    [[ ! $summary ]] || echo "$summary" # no fmt
    printf "$usageLineFmt" "$progName" "$args"
    local pos name ; while IFS=' ' read -u3 -r pos spec ; do
        local description=${allowedArgs[$spec]}
        if [[ $columns ]] ; then description=$( fmt --width=$(( columns - 8 )) --goal=$(( columns - 8 )) <<<"$description" ) ; fi
        printf '    %s\n        %s\n' "$spec" "${description//$'\n'/$'\n        '}"
    done 3< <( if ! type -t sort &>/dev/null ; then
        for spec in "${!allowedArgs[@]}" ; do printf '%s %s\n' x "$spec" ; done
    else for spec in "${!allowedArgs[@]}" ; do
        name=${spec%%=*} ; printf '%s %s\n' "${name##* }" "$spec"
    done | LC_ALL=C sort ; fi )
    if [[ ${shortArgsAre:-} && ${shortArgsAre,,} == flags ]] ; then
        printf '    %s\n        %s\n' "-h, -?, --help" "Do nothing but print this message and exit with success."
    else
        printf '    %s\n        %s\n' "--help" "Do nothing but print this message and exit with success."
    fi
    if [[ $details ]] ; then if [[ $columns ]] ; then
        local line ; while IFS='' read -r line ; do # wrap at words and with indentation, but keep original line breaks
            fmt --width=$columns --goal=$columns --prefix='    ' --split-only --uniform-spacing <<<"$line"
        done <<<"$details"
    else
        echo "$details"
    fi ; fi
    \exit 0
}
