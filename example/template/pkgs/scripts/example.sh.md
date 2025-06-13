: << '```bash'

# TODO: title

TODO: replace the program below or remove this file
The `@{...}` will be processed by `substituteImplicit`.


## Implementation

```bash
set -o pipefail -u

echo "This is only an example, replace me!" >&2 ; exit 1

description="Pushes a Nix »flake« (default: .) and its local inputs to a remote »target« host's /nix/store.
"
argvDesc='target [flake]'
declare -g -A allowedArgs=(
    [--types=indirect,path,git+ssh]="The types of input flakes that will be pushed. Should include all types that the remote won't be able to pull itself."
    [--register[=<name>]]="Register the flake in the target's (user) flake registry as »name«, or the name of the flake directory as inferred from »\$flake«. The »\$target« has to be an SSH [user@]hostname/IP. Specifically, this (re-)places an entry »from:{type:indirect,id:\$name},to:<pushed>« in »\$target:.config/nix/registry.json«."
)
details="
»target« can be a plain (SSH) [user@]hostname/IP or any valid Nix store URL.
»flake« should be a local filesystem path. It can also be a »git+file://«-URL, in which case »dir« is the only supported parameter. Defaults to ».«.
"

generic-arg-parse "$@" || exit
generic-arg-help "push-flake" "$argvDesc" "$description" "$details" || exit
exitCode=2 generic-arg-verify || exit

targetStore=${argv[0]:?}
if [[ $targetStore != *://* ]] ; then
    targetStore='ssh://'$targetStore
elif [[ ${args[register]:-} ]] ; then
    echo "--register can't be used with explicit nix store URL as »target«" ; exit 1
fi

flakeSpec=${argv[1]:-.}
if [[ $flakeSpec == git+file:///* ]] ; then
    flakeLock=${flakeSpec##git+file://}
    flakeLock=${flakeLock/?dir=//}/flake.lock
else
    flakeSpec=$( @{pkgs.coreutils}/bin/realpath "$flakeSpec" ) || exit
    flakeSpec=$( while true ; do # (this is how nix behaves when passed any type of (non-URL) path)
    	if [[ -e flake.nix ]] ; then echo "$PWD" ; break ; fi
        cd .. ; if [[ $PWD == / ]] ; then echo 'Unable to locate a flake.nix in (parent of) provided path' >&2 ; exit 2 ; fi
    done ) || exit
    flakeLock=$flakeSpec/flake.lock
    if [[ -e $flakeSpec/.git ]] ; then
        flakeSpec=git+file://$flakeSpec # required for builtins.getFlake to heed the git index (and thus .gitignore)
    fi
fi

storePaths=( $( PATH=@{pkgs.git}/bin:$PATH @{pkgs.nix}/bin/nix --extra-experimental-features 'nix-command flakes' eval --impure --expr '{ flakeLock, flakeSpec, localTypes, }: { result = let
    lock = builtins.fromJSON (builtins.readFile flakeLock);
    flake = builtins.getFlake flakeSpec; inherit (flake) inputs;
    to-outPath = builtins.listToAttrs (map (input: { name = input.narHash; value = input.outPath; }) (let getInputs = flake: [ flake ] ++ (map getInputs (builtins.attrValues (flake.inputs or { }))); in flatten (map getInputs (builtins.attrValues inputs))));
    flatten = x: if builtins.isList x then builtins.concatMap (y: flatten y) x else [ x ];
    types = builtins.filter builtins.isString (builtins.split "," localTypes);
in builtins.concatStringsSep " " ([ flake.outPath ] ++ (map (name: (
    to-outPath.${lock.nodes.${name}.locked.narHash}
)) (
    builtins.filter (name: lock.nodes.${name}?original && ((builtins.elem lock.nodes.${name}.original.type types) || (builtins.elem "git+ssh" types && lock.nodes.${name}.original.type == "git" && builtins.substring 0 6 lock.nodes.${name}.original.url == "ssh://"))) (builtins.attrNames lock.nodes)
))); }' --argstr flakeLock "$flakeLock" --argstr flakeSpec "$flakeSpec" --argstr localTypes "${args[types]:-indirect,path,git+ssh}" --raw -- result ) ) || exit
: ${storePaths[0]:?}

if [[ ${args[register]:-} ]] ; then storePaths+=( @{pkgs.jq} ) ; fi

PATH=@{pkgs.openssh}/bin:@{pkgs.hostname-debian}/bin:@{pkgs.gnugrep}/bin:$PATH @{pkgs.nix}/bin/nix --extra-experimental-features 'nix-command flakes' copy --to "$targetStore" ${storePaths[@]} || exit
# ¿¿Why does something there call »hostname -I«, which is apparently only available in the debian version of hostname??
printf %s ${storePaths[0]}

if [[ ${args[register]:-} ]] ; then
    if [[ ${args[register]:-} == 1 ]] ; then args[register]=$( basename "$( dirname "$flakeLock" )" ) ; fi

    ssh -q -t "${argv[0]:?}" -- "$( function remote { set -o pipefail -u
        jq=$1 ; shift ; path=$1 ; shift ; name=$1 ; shift ; args=( --arg path "$path" --arg name "$name" )
        if ! $jq --version &>/dev/null ; then jq=$( nix --extra-experimental-features 'nix-command flakes' build nixpkgs#jq^bin --no-link --print-out-paths )/bin/jq ; fi # fallback for e.g. cross-arch
        if [[ -e .config/nix/registry.json ]] ; then reg=$(<.config/nix/registry.json) ; else reg='{ "version": 2, "flakes": [ ] }' ; fi
        isVer=$( <<<$reg $jq .version ) ; if [[ $isVer != 2 ]] ; then echo "Unexpected flake registry's version ${isVer:-(empty)}" ; exit 2 ; fi

        if [[ $( <<<$reg $jq "${args[@]}" '.flakes[] | select(.from.type == "indirect" and .from.id == $name)' ) ]] ; then
            reg=$( <<<$reg $jq "${args[@]}" '( .flakes[] | select(.from.type == "indirect" and .from.id == $name) ).to |= { type: "path", path: $path, }' )
        else
            reg=$( <<<$reg $jq "${args[@]}" '.flakes += [ { from: { type: "indirect", id: $name }, to: { type: "path", path: $path, } } ]' )
        fi
        mkdir -p .config/nix/ ; <<<$reg cat >.config/nix/registry.json
    } ; declare -f remote ) ; remote $( printf ' %q' @{pkgs.jq}/bin/jq "${storePaths[0]}" "${args[register]}" )" || exit

    printf ' == %s' "${args[register]}"
fi

printf '\n'
