## Performs post-processing and basic verification of the named arguments passed by the user and parsed by »generic-arg-parse«, based on the declarations in the associative array »allowedArgs«.
#  Entries in »allowedArgs« should have the form »["[-l, ]--name[ ...]"]="description"« for boolean flags, and »["[-l, ]--name=VAL[ ...]"]="description"« for string options (but »generic-arg-parse« currently only supports either flags or options to have short forms).
#  »description« is used by »generic-arg-help«. Boolean flags may only have the values »1« (as set by »generic-ags-parse« for flags without value) or be empty (specified on the CLI with an explicit empty value or the prefix »--no-«).
#  »VAL« is purely nominal (but may not contain spaces). Any argument passed that is not in »allowedArgs« or matched by the regex in the named input variable »allowedUndeclaredArgs« (regex) raises an error.
function generic-arg-verify { # 1?: exitCodeOnError
    local exitCode=${exitCodeOnError:-${exitCode:-${1:-1}}}
    # allowedUndeclaredArgs=regex

    local spec ; for spec in "${!allowedArgs[@]}" ; do
        local description=${allowedArgs[$spec]} ; unset allowedArgs["$spec"]
        local isBool=1 ; if [[ $spec == *'='* ]] ; then isBool= ; fi
        local isList= ; if [[ $spec == *'='*' ...' ]] ; then isList=1 ; fi
        spec=${spec%%=*} ; spec=${spec%%[}
        if [[ $spec =~ ^-([^-]),' '-- ]] ; then
            spec=${spec#*, } ; local shortName=${BASH_REMATCH[1]}
        else local shortName= ; fi
        local longName=${spec#--}
        allowedArgs[$spec]="$description"

        if [[ ! $isList ]] ; then # use last
            if [[ $shortName && -v shortArgs[$shortName] ]] ; then
                local i ; for (( i=$(( ${#argsOrder[@]} - 1 )) ; i>=0 ; i-- )) ; do
                    if [[ ${argsOrder[$i]} == "$shortName" ]] ; then
                        args[$longName]=${shortArgs[$shortName]} ; break
                    elif [[ ${argsOrder[$i]} == "$longName" ]] ; then break ; fi
                done
                unset shortArgs[$shortName]
            fi
            if [[ $isBool ]] ; then
                if [[ ${args[$longName]:-} != 1 && ${args[$longName]:-} != '' ]] ; then
                    echo "Argument »--$longName« should be a boolean, but its value is: ${args[$longName]}" 1>&2 ; \return $exitCode
                fi
            fi
        else # merge
            local -n argvLongName=argv_${longName//-/_}
            if [[ -v args[$longName] ]] ; then argvLongName+=( "${args[$longName]}" ) ; fi
            if [[ $shortName && -v shortArgs[$shortName] ]] ; then
                local -n argvShortName=argv_$shortName
                argvShortName+=( "${shortArgs[$shortName]}" )
                local -a final=( ) ; local name ; for name in "${argsOrder[@]}" ; do
                    if [[ $name == "$shortName" ]] ; then
                        final+=( "${argvShortName[0]}" ) ; argvShortName=( "${argvShortName[@]:1}" )
                    elif [[ $name == "$longName" ]] ; then
                        final+=( "${argvLongName[0]}" ) ; argvLongName=( "${argvLongName[@]:1}" )
                    fi
                done ; argvLongName=( "${final[@]}" )
                unset shortArgs[$shortName]
            fi
            if [[ -v argv_${longName//-/_} && ${dupEmptyResets:-} ]] ; then
                local hadDupe= ; local i ; for (( i=$(( ${#argvLongName[@]} - 1 )) ; i>=0 ; i-- )) ; do
                    if [[ ${argvLongName[$i]} == '' ]] ; then hadDupe=1 ; fi
                    if [[ $hadDupe ]] ; then unset argvLongName[$i] ; fi # but leave indices as they are
                done
            fi
            if [[ ${!argvLongName[@]} > 0 ]] ; then args[$longName]=1 ; else args[$longName]= ; fi
        fi
    done

    if [[ ${!shortArgs[@]} ]] ; then # (false if shortArgs is unset or empty)
        { echo -n "Unexpected short arguments:" ; printf ' -%s' "${!shortArgs[@]}" ; echo ".${allowedArgs[help]:+ Call with »--help« for a list of valid arguments.}" ; } 1>&2 ; \return $exitCode
    fi ; unset shortArgs

    local name ; for name in "${!args[@]}" ; do
        if [[ ${allowedArgs[--$name]:-} ]] ; then continue ; fi
        if [[ ${allowedUndeclaredArgs:-} && $name =~ $allowedUndeclaredArgs ]] ; then continue ; fi
        echo "Unexpected argument »--$name«.${allowedArgs[help]:+ Call with »--help« for a list of valid arguments.}" 1>&2 ; \return $exitCode
    done
}
