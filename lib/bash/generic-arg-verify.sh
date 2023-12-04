## Performs a basic verification of the named arguments passed by the user and parsed by »generic-arg-parse« against the names in »allowedArgs«.
#  Entries in »allowedArgs« should have the form »[--name]="description"« for boolean flags, and »[--name=VAL]="description"« for string arguments.
#  »description« is used by »generic-arg-help«. Boolean flags may only have the values »1« (as set by »generic-ags-parse« for flags without value) or be empty.
#  »VAL« is purely nominal. Any argument passed that is not in »allowedArgs« raises an error.
function generic-arg-verify { # 1?: exitCode
    local exitCode=${exitCode:-${1:-1}}
    local names=' '"${!allowedArgs[@]}"
    for name in "${!args[@]}" ; do
        if [[ ${allowedArgs[--$name]:-} ]] ; then
            if [[ ${args[$name]} == '' || ${args[$name]} == 1 ]] ; then continue ; fi
            echo "Argument »--$name« should be a boolean, but its value is: ${args[$name]}" 1>&2 ; \return $exitCode
        fi
        if [[ $names == *' --'"$name"'='* || $names == *' --'"$name"'[='* ]] ; then continue ; fi
        if [[ ${undeclared:-} && $name =~ $undeclared ]] ; then continue ; fi
        echo "Unexpected argument »--$name«.${allowedArgs[help]:+ Call with »--help« for a list of valid arguments.}" 1>&2 ; \return $exitCode
    done
}
