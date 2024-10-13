dirname: inputs: let
    inherit (inputs.nixpkgs) lib;
in {

    ## Creates a project's »node_modules« based only on it's »package-lock.json« (and its hash), so that changes in the rest of the project don't cause a lengthy rebuild of the »node_modules« tree.
    #  Also returns a »passthru.devShell« that, upon activision, replaces the local »$PWD/node_modules« with a shallow, read-only copy of the in-store »node_modules«.
    #  By calling »./node_modules/make-mutable«, this made writable, using a combination of FUSE overlays -- near instantaneously, without copying anything.
    #  Normal »npm« commands can then update the writable tree, which should result in changes to the »package-lock.json«.
    #  After calling »./node_modules/make-immutable« (or »umount ./node_modules«, if the link to the script was removed by npm), which discards the changes to the local »node_modules«, the changes to the »package-lock.json« can be committed to »package-lock.hash« by calling »./node_modules/commit-lock«.
    #  All that is required to apply the changes to the nix build of »node_modules« is to read »npmDepsHash« from »package-lock.hash« (the default).
    #  If »flakeOutput« is set, then »./node_modules/commit-lock« will automatically rebuild and apply »node_modules«.
    mk-node_modules = {
        pkgs, nodejs ? pkgs.nodejs, # Package set and nodejs version to use.
        sourceRoot ? null, # Optional. Only used in the defaults for »packageLock« and »npmDepsHash«, and for »passthru.withSource«.
        packageJson ? builtins.path { path = "${sourceRoot}/package.json"; name = "package.json"; }, # »package.json« as individual store path (use a literal (unquoted) path or »builtins.path«).
        packageLock ? builtins.path { path = "${sourceRoot}/package-lock.json"; name = "package-lock.json"; }, # »package-lock.json« as individual store path (use a literal (unquoted) path or »builtins.path«).
        npmDepsHash ? lib.fileContents "${sourceRoot}/package-lock.hash", # Hash, as created in »package-lock.hash« by »commit-lock« after changing »package-lock.json«.
        extraArgs ? { }, # Additional/overriding arguments to pass to »pkgs.buildNpmPackage«.
        extraShellHook ? "", # Additional commands to execute at the end of the »devShell«'s »shellHook«.
        flakeOutput ? null, # Optional. Relative flake output path of this package. E.g.: »./nixos#packages.${pkgs.system}.default«.
    }: let
        node_modules-prod = let node_modules = (pkgs.buildNpmPackage.override { inherit nodejs; }) ({
            name = "node_modules-prod"; NODE_ENV = "production";
            inherit npmDepsHash; src = pkgs.runCommandLocal "package-lock" { } ''
                mkdir -p $out
                ln -sT ${packageJson} $out/package.json
                ln -sT ${packageLock} $out/package-lock.json
            '';

            # Compatibility options:
            makeCacheWritable = false;
            npmPackFlags = [ "--ignore-scripts" ];
            npmFlags = [ "--legacy-peer-deps" ]; # "--loglevel=verbose"
            NODE_OPTIONS = "--openssl-legacy-provider";

            dontNpmBuild = true;
            installPhase = ''
                runHook preInstall
                mkdir -p $out ; cp -rT node_modules/ $out/node_modules/
                runHook postInstall
            '';
        } // extraArgs // (rec {
            passthru = {
                inherit node_modules-dev node_modules-prod nodejs extraShellHook devShell;
                withSource = name: commands: pkgs.runCommandLocal name { inherit passthru; } ''
                    mkdir -p $out ${lib.optionalString (sourceRoot != null) ''; cp -aT ${sourceRoot}/ $out/ ; chmod -R +w $out''}
                    ln -sT ${node_modules}/node_modules $out/node_modules
                    if [[ -e $out/bin ]] ; then sed -i 's;/usr/bin/env node;${node_modules.passthru.nodejs}/bin/node;g' $out/bin/* ; fi
                    ${commands}
                '';
            } // (extraArgs.passthru or { });
            nativeBuildInputs = (extraArgs.nativeBuildInputs or [ ]) ++ (lib.attrVals [ "pkg-config" "python3" ] pkgs.buildPackages);
        })); in node_modules;

        node_modules-dev = node_modules-prod.overrideAttrs {
            name = "node_modules-dev"; NODE_ENV = "development";
        } // extraArgs;

        devShell = pkgs.mkShell {
            nativeBuildInputs = [ nodejs pkgs.bindfs ];
            passthru = node_modules-prod.passthru;
            shellHook = let
                make-mutable = pkgs.writeShellScript "make-mutable" ''
                    set -u -o pipefail
                    node_modules=''${1:-$( cd "$( dirname -- "$0" )" ; pwd )}
                    ${make-immutable} "$node_modules"
                    hash=( $( <<<"$node_modules" ${pkgs.coreutils}/bin/sha256sum - ) ) ; hash=''${hash[0]}
                    upperdir=/tmp/$hash.lower ; rm -rf $upperdir && mkdir $upperdir || exit
                    workdir=/tmp/$hash.work ; rm -rf $workdir && mkdir $workdir || exit
                    middledir=/tmp/$hash.middle ; mkdir -p $middledir || exit
                    lowerdir=${node_modules-dev}/node_modules
                    ${pkgs.bindfs}/bin/bindfs -o force-user=$(id -u),force-group=$(id -g),perms=u+w:o-rwx,no-allow-other "$lowerdir" $middledir || exit
                    chmod 750 "$node_modules"
                    ${pkgs.fuse-overlayfs}/bin/fuse-overlayfs -o lowerdir=$middledir,upperdir=$upperdir,workdir=$workdir "$node_modules" || exit
                    ln -sfT ${make-immutable} "$node_modules"/make-immutable || exit
                '';
                    #${pkgs.fuse-overlayfs}/bin/fuse-overlayfs -o squash_to_uid=$(id -u),squash_to_gid=$(id -g),lowerdir=$lowerdir,upperdir=$upperdir,workdir=$workdir "$node_modules" || exit
                    #${pkgs.fuse-overlayfs}/bin/fuse-overlayfs -o uidmapping=0:$(id -u):1,gidmapping=0:$(id -g):1,lowerdir=$lowerdir,upperdir=$upperdir,workdir=$workdir "$node_modules" || exit
                make-immutable = pkgs.writeShellScript "make-immutable" ''
                    set -u -o pipefail
                    node_modules=''${1:-$( cd "$( dirname -- "$0" )" ; pwd )}
                    while mountpoint -q "$node_modules" ; do umount "$node_modules" || exit ; done
                    chmod 555 "$node_modules"
                    hash=( $( <<<"$node_modules" ${pkgs.coreutils}/bin/sha256sum - ) ) ; hash=''${hash[0]}
                    middledir=/tmp/$hash.middle
                    while mountpoint -q $middledir ; do umount $middledir || exit ; done
                '';
                commit-lock = pkgs.writeShellScript "commit-lock" ''
                    set -u -o pipefail
                    node_modules=''${1:-$( cd "$( dirname -- "$0" )" ; pwd )}
                    ${pkgs.prefetch-npm-deps}/bin/prefetch-npm-deps "$node_modules"/../package-lock.json 2>/dev/null >"$node_modules"/../package-lock.hash || exit
                    ${if flakeOutput != null then ''
                        ${apply-node_modules ''"$( nix --extra-experimental-features 'nix-command flakes' build "$node_modules"/../${flakeOutput}.passthru.node_modules-dev --no-link --print-out-paths )"'' (placeholder "out")}
                    '' else ''
                        echo 'Re-open your "nix develop" shell to use the new node_modules!'
                    ''}
                '';
                    #eval "$( nix --extra-experimental-features 'nix-command flakes' eval "$node_modules"/../nixos#devShells.${localSystem}.default.shellHook --no-eval-cache --raw )"
                apply-node_modules = node_modules: commit-lock: ''
                    if [[ -e $node_modules ]] ; then ${make-immutable} "$node_modules" ; fi
                    ( chmod u+w "$node_modules" ; rm -rf "$node_modules" ) &>/dev/null ; mkdir "$node_modules" || exit
                    ( shopt -s dotglob ; ln -st "$node_modules" ${node_modules}/node_modules/* ) || exit
                    ln -sfT ${make-mutable} "$node_modules"/make-mutable || exit
                    ln -sfT ${commit-lock} "$node_modules"/commit-lock || exit
                    chmod 555 "$node_modules" || exit
                '';
                    #${pkgs.rsync}/bin/rsync --archive --delete --force ${node_modules}/node_modules/ "$node_modules"/ || exit
            in ''
                node_modules=$( while true ; do
                	if [[ -e package.json ]] ; then echo "$PWD" ; break ; fi
                	cd .. ; if [[ $PWD == / ]] ; then echo 'Unable to locate a package.json in (parent of) CWD' >&2 ; exit 2 ; fi
                done )/node_modules || exit
                ( ${apply-node_modules node_modules-dev commit-lock} ) || exit
                PATH=$node_modules/.bin:$PATH
                ${extraShellHook}
            '';
        };
    in node_modules-prod;

}
