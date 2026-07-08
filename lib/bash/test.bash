#!/usr/bin/env bash
set -u -o pipefail

failed=
function failed {
    echo "Test failed with exit code $?" 1>&2
    declare -p printShortFlag printShortOpt inputArgs
    failed=1 ; exit 1
}

function varAsExpected {
    local varName=$1 ; local expectedVarName=expected_$varName
    local expected=$( declare -p $expectedVarName )
    diff <(declare -p $varName) <( echo "${expected/expected_/}" )
}

#set -x
function run-test { inputArgs=( "$@" ) ; (
    declareAllowedArgs
    #declare -p allowedArgs #; exit 1
    shortArgsAre=FlAgS ; if [[ $printShortOpt != : ]] ; then shortArgsAre=options ; fi

    PATH= exitCodeOnError=2 shortArgsAre=$shortArgsAre dupOptsAre=lists generic-arg-parse "$@" || exit
    shortArgsAre=$shortArgsAre generic-arg-help "binaryName" "argvDesc" "$summary" "$details" || exit
    PATH= exitCodeOnError=2 dupEmptyResets=1 generic-arg-verify || exit

    for var in args argv argv_dup_e argv_dup_f ; do
        varAsExpected $var || exit
    done
) }

dir=$(dirname "$0") ; cd "$dir" || exit
source ./generic-arg-parse.sh || exit
source ./generic-arg-help.sh || exit
source ./generic-arg-verify.sh || exit

summary= ; details=
function declareAllowedArgs {
    declare -g -A allowedArgs=(
        [$( $printShortFlag '-a, ' )--flag-a]="Description of flag-a"
        [$( $printShortFlag '-b, ' )--flag-b]="Description of flag-b"
        [$( $printShortOpt  '-c, ' )--opt-c=]="Description of opt-c with value"
        [$( $printShortOpt  '-d, ' )--opt-d=VAL]="Description of opt-d with value"
        [$( $printShortOpt  '-e, ' )--dup-e=VAL ...]="Description of dup-e that can be repeated."$'\n'"With a second line of description."
        [$( $printShortOpt  '-f, ' )--dup-f=VAL ...]="Description of dup-f that can be repeated. This description is long enough to be wrapped and indented when printed. Hopefully, if this is enough text, it will be wrapped and indented properly. "
    )
}
declare -A expected_args=(
    [flag-a]=
    [flag-b]=1
    [opt-c]=bar
    [opt-d]=baz
    [dup-e]=1
    [dup-f]=1
)
declare -a expected_argv=( pos1 pos2 )
declare -a expected_argv_dup_e=( 1 2 5 )
declare -a expected_argv_dup_f=( [2]=3 [3]=4 [4]=6 ) # 0 and 1 unset

printShortFlag='echo -nE' ; printShortOpt=:
run-test --flag-a --no-flag-b pos1 --flag-b --no-flag-a --opt-c=foo --dup-e=1 --dup-e=2 --dup-f=x --dup-f='' --dup-f=3 --dup-f=4 --opt-c=bar pos2 --opt-d=baz --dup-e=5 --dup-f=6 || failed
run-test       -a          -B pos1       -b          -A --opt-c=foo --dup-e=1 --dup-e=2 --dup-f=x --dup-f='' --dup-f=3 --dup-f=4 --opt-c=bar pos2 --opt-d=baz --dup-e=5 --dup-f=6 || failed
run-test --flag-a --no-flag-b pos1       -b          -A --opt-c=foo --dup-e=1 --dup-e=2 --dup-f=x --dup-f='' --dup-f=3 --dup-f=4 --opt-c=bar pos2 --opt-d=baz --dup-e=5 --dup-f=6 || failed
run-test       -a          -B pos1 --flag-b --no-flag-a --opt-c=foo --dup-e=1 --dup-e=2 --dup-f=x --dup-f='' --dup-f=3 --dup-f=4 --opt-c=bar pos2 --opt-d=baz --dup-e=5 --dup-f=6 || failed
printShortFlag=: ; printShortOpt='echo -nE'
run-test --flag-a --no-flag-b pos1 --flag-b --no-flag-a --opt-c=foo --dup-e=1 --dup-e=2 --dup-f=x --dup-f='' --dup-f=3 --dup-f=4 --opt-c=bar pos2 --opt-d=baz --dup-e=5 --dup-f=6 || failed
run-test --flag-a --no-flag-b pos1 --flag-b --no-flag-a      -c foo      -e 1      -e 2      -f x      -f ''      -f 3      -f 4      -c bar pos2      -d baz      -e 5      -f 6 || failed
run-test --flag-a --no-flag-b pos1 --flag-b --no-flag-a      -c foo      -e 1      -e 2      -f x --dup-f='' --dup-f=3      -f 4      -c bar pos2      -d baz      -e 5      -f 6 || failed
run-test --flag-a --no-flag-b pos1 --flag-b --no-flag-a      -c foo --dup-e=1      -e 2 --dup-f=x      -f '' --dup-f=3      -f 4 --opt-c=bar pos2      -d baz --dup-e=5      -f 6 || failed
run-test --flag-a --no-flag-b pos1 --flag-b --no-flag-a --opt-c=foo --dup-e=1 --dup-e=2      -f x      -f '' --dup-f=3 --dup-f=4      -c bar pos2 --opt-d=baz      -e 5 --dup-f=6 || failed
{ ! run-test --undeclared ; } || failed

summary='this should be about one line of text. Maybe even two, printed exactly as passed, but not more than that. It should be printed before the usage line.'
# spellchecker: disable
details='
Description:
    Short line: Sed non risus.
    Short-ish line: Lorem ipsum dolor sit amet, consectetur adipiscing elit.

    Long line (should be wrapped and indented): Suspendisse lectus tortor, dignissim sit amet, adipiscing nec, ultricies sed, dolor. Cras elementum ultrices diam. Maecenas ligula massa, varius a, semper congue, euismod non, mi. Proin porttitor, orci nec nonummy molestie, enim est eleifend mi, non fermentum diam nisl sit amet erat. Duis semper.
    Duis arcu massa, scelerisque vitae, consequat in, pretium a, enim. Pellentesque congue.
    Ut in risus volutpat libero pharetra tempor. Cras vestibulum bibendum augue. Praesent egestas leo in pede.
    Praesent blandit odio eu enim. Pellentesque sed dui ut augue blandit sodales. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Aliquam nibh. Mauris ac mauris sed pede pellentesque fermentum. Maecenas adipiscing ante non diam sodales hendrerit.
'
# spellchecker: enable
{ ! run-test -h &>/dev/null ; } || failed
printShortFlag='echo -nE' ; printShortOpt=:
COLUMNS=80 run-test --help || failed
PATH= COLUMNS=80 run-test --help || failed # can work without external programs
run-test -h &>/dev/null || failed
run-test -? &>/dev/null || failed
