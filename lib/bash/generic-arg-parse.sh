## Performs a (no longer that) simple but still generic parsing of CLI arguments. Creates a global associative array »args« and a global normal array »argv«.
#  Named arguments may be passed as »--[no-]name[=value]«, where »value« defaults to »1« (or empty with »no«), and are assigned as »args[name]=value«.
#  Everything else, or everything following the »--« argument, ends up as positional arguments in »argv«.
#  Duplicate flags (args without value) override earlier ones. Treatment of duplicate options (args with value) depends on the variable »$dupOptsAre«: By default, they also overwrite, with »error« they abort parsing. With »lists« they add the previous value to the list »$argv_$name«.
#  Short args (those with a single leading dash) are treated according to »$shortArgsAre«: By default, they are normal positional arguments. With »flags« they must be a single letter long and set »shortArgs[letter]=1«. With »options they must be a single letter and set »shortArgs[letter]« to the value of the next argument (»dupOptsAre« logic applies). With »error« any option before »--« that starts with a single dash aborts parsing.
#  The parsing is generic in so far as that it does not depend on a declaration of allowed args; checking the validity of the parsed arguments is up to the caller.
#  See »generic-arg-help« and »generic-arg-verify«.
function generic-arg-parse { # ...
    declare -p args &>/dev/null || declare -g -A args=( ) ; declare -p argv &>/dev/null || declare -g -a argv=( ) ; declare -p argsOrder &>/dev/null || declare -g -a argsOrder=( ) # these end up in the caller's scope
    if [[ ${shortArgsAre:-} == flags || ${shortArgsAre:-} == FlAgS || ${shortArgsAre:-} == options ]] ; then declare -g -A shortArgs ; fi
    if [[ ${shortOptsAre:-} ]] ; then echo "The »shortOptsAre« was renamed to »shortArgsAre«." 1>&2 ; \return 1 ; fi
    # ${dupOptsAre:-override} or lists or error
    while (( "$#" )) ; do
        if [[ $1 == -- ]] ; then shift ; argv+=( "$@" ) ; \return 0 ; fi
        if [[ $1 == --* ]] ; then
            if [[ $1 == *=* ]] ; then
                local name=${1%%=*} ; name=${name#--} ; local value=${1#--$name=}
                if [[ -v args[$name] ]] ; then
                    if [[ ${dupOptsAre:-} == error ]] ; then
                        echo "Duplicate argument: --$name" >&2 ; \return ${exitCodeOnError:-1}
                    elif [[ ${dupOptsAre:-} == lists ]] ; then
                        local -n argvName=argv_${name//-/_}
                        argvName+=( "${args[$name]}" ) # save previous
                    fi # else override by default
                fi
                args[$name]=$value ; argsOrder+=( "$name" )
            else
                if [[ $1 == --no-* ]] ; then
                    args[${1#--no-}]='' ; argsOrder+=( "${1#--no-}" )
                else
                    args[${1#--}]=1 ; argsOrder+=( "${1#--}" )
                fi
            fi
        elif [[ $1 == -* ]] ; then
            if [[ ${shortArgsAre:-} == flags || ${shortArgsAre:-} == FlAgS ]] ; then
                if (( "${#1}" > 2 )) ; then
                    echo "Short flags must be single letters: $1" >&2 ; \return ${exitCodeOnError:-1}
                fi
                local name=${1#-} value=1
                if [[ ${shortArgsAre:-} == FlAgS && $name != ${name,,} ]] ; then name=${name,,} ; value='' ; fi
                shortArgs[$name]=$value ; argsOrder+=( "$name" )
            elif [[ ${shortArgsAre:-} == options ]] ; then
                if (( "${#1}" > 2 )) ; then
                    echo "Short options must be single letters: $1" >&2 ; \return ${exitCodeOnError:-1}
                fi
                if (( "$#" < 2 )) ; then
                    echo "Missing value for short option: $1" >&2 ; \return ${exitCodeOnError:-1}
                fi
                local name=${1#-} ; shift ; local value=$1
                if [[ -v shortArgs[$name] ]] ; then
                    if [[ ${dupOptsAre:-} == error ]] ; then
                        echo "Duplicate argument: -$name" >&2 ; \return ${exitCodeOnError:-1}
                    elif [[ ${dupOptsAre:-} == lists ]] ; then
                        local -n argvName=argv_$name
                        argvName+=( "${shortArgs[$name]}" ) # save previous
                    fi # else override by default
                fi
                shortArgs[$name]=$value ; argsOrder+=( "$name" )
            elif [[ ${shortArgsAre:-} == error ]] ; then
                echo "Unexpected short option: $1" >&2 ; \return ${exitCodeOnError:-1}
            else argv+=( "$1" ) ; fi
        else
            argv+=( "$1" )
            argsOrder+=( '' )
        fi
    shift ; done
}
