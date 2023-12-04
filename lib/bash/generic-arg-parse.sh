## Performs a simple and generic parsing of CLI arguments. Creates a global associative array »args« and a global normal array »argv«.
#  Named options may be passed as »--name[=value]«, where »value« defaults to »1«, and are assigned to »args«.
#  Everything else, or everything following the »--« argument, ends up as positional arguments in »argv«.
#  Checking the validity of the parsed arguments is up to the caller.
function generic-arg-parse { # ...
    declare -g -A args=( ) ; declare -g -a argv=( ) # this ends up in the caller's scope
    while (( "$#" )) ; do
        if [[ $1 == -- ]] ; then shift ; argv+=( "$@" ) ; \return 0 ; fi
        if [[ $1 == --* ]] ; then
            if [[ $1 == *=* ]] ; then
                local key=${1/=*/} ; args[${key/--/}]=${1/$key=/}
            else args[${1/--/}]=1 ; fi
        else argv+=( "$1" ) ; fi
    shift ; done
}
