## Performs a simple and generic parsing of CLI arguments. Creates a global associative array »args« and a global normal array »argv«.
#  Named options may be passed as »--name[=value]«, where »value« defaults to »1«, and are assigned as »args[name]=value«.
#  Everything else, or everything following the »--« argument, ends up as positional arguments in »argv«.
#  Checking the validity of the parsed arguments is up to the caller.
function generic-arg-parse { # ...
    declare -g -A args=( ) ; declare -g -a argv=( ) # this ends up in the caller's scope
    if [[ ${shortOptsAre:-} == "flags" || ${shortOptsAre:-} == "options" ]] ; then declare -g -A shortArgs=( ) ; fi
    while (( "$#" )) ; do
        if [[ $1 == -- ]] ; then shift ; argv+=( "$@" ) ; \return 0 ; fi
        if [[ $1 == --* ]] ; then
            if [[ $1 == *=* ]] ; then
                local name=${1/=*/} ; args[${name/--/}]=${1/$name=/}
            else args[${1/--/}]=1 ; fi
        elif [[ $1 == -* ]] ; then
            if [[ ${shortOptsAre:-} == flags ]] ; then
                if (( "${#1}" > 2 )) ; then
                    echo "Short options must be single letters: $1" >&2 ; \return ${exitCodeOnError:-1}
                fi
                shortArgs[${1/-/}]=1
            elif [[ ${shortOptsAre:-} == options ]] ; then
                if (( "$#" < 2 )) ; then
                    echo "Missing value for short option: $1" >&2 ; \return ${exitCodeOnError:-1}
                fi
                shortArgs[${1/-/}]=$2 ; shift
            elif [[ ${shortOptsAre:-} == error ]] ; then
                echo "Unexpected short option: $1" >&2 ; \return ${exitCodeOnError:-1}
            else argv+=( "$1" ) ; fi
        else argv+=( "$1" ) ; fi
    shift ; done
}
