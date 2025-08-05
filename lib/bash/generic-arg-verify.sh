## Performs a basic verification of the named arguments passed by the user and parsed by »generic-arg-parse« against the names in »allowedArgs«.
#  Entries in »allowedArgs« should have the form »[--name]="description"« for boolean flags, and »[--name=VAL]="description"« for string arguments.
#  »description« is used by »generic-arg-help«. Boolean flags may only have the values »1« (as set by »generic-ags-parse« for flags without value) or be empty.
#  »VAL« is purely nominal. Any argument passed that is not in »allowedArgs« raises an error.
function generic-arg-verify { # 1?: exitCodeOnError
    local exitCode=${exitCodeOnError:-${exitCode:-${1:-1}}}
    if  declare -p shortArgs &>/dev/null ; then # (dunno how to make a better test for this)
        local spec ; for spec in "${!allowedArgs[@]}" ; do
            local names=${spec%=*} ; names=${names%[} ; if [[ $names =~ ^-([^-]),' '-- ]] ; then
                local description=${allowedArgs[$spec]} ; unset allowedArgs[$spec]
                allowedArgs[${spec#*, }]="$description"
                local shortName=${BASH_REMATCH[1]} ; local longName=${names#*, --}
                if [[ ${shortArgs[$shortName]:-} ]] ; then
                    if [[ ${args[$longName]:-} ]] ; then
                        echo "Short option »-$shortName« conflicts with long option »--$longName«" 1>&2 ; \return $exitCode
                    fi
                    args[$longName]=${shortArgs[$shortName]}
                    unset shortArgs[$shortName]
                fi
            fi
        done
        if (( ${#shortArgs[@]} > 0 )) ; then
            { echo -n "Unexpected short options:" ; printf ' -%s' "${!shortArgs[@]}" ; echo ; } 1>&2 ; \return $exitCode
        fi
    fi

    local names=' '"${!allowedArgs[@]}"' '
    local name ; for name in "${!args[@]}" ; do
        if [[ ${allowedArgs[--$name]:-} ]] ; then
            if [[ ${args[$name]} == '' || ${args[$name]} == 1 ]] ; then continue ; fi
            echo "Argument »--$name« should be a boolean, but its value is: ${args[$name]}" 1>&2 ; \return $exitCode
        fi
        if [[ $names == *' --'"$name"'='* || $names == *' --'"$name"'[='* ]] ; then continue ; fi
        if [[ ${allowedUndeclaredArgs:-} && $name =~ $allowedUndeclaredArgs ]] ; then continue ; fi
        echo "Unexpected argument »--$name«.${allowedArgs[help]:+ Call with »--help« for a list of valid arguments.}" 1>&2 ; \return $exitCode
    done
}
