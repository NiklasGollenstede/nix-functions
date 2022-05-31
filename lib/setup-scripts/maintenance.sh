
##
# NixOS Maintenance
##

## On the host and for the user it is called by, creates/registers a VirtualBox VM meant to run the shells target host. Requires the path to the target host's »diskImage« as the result of running the install script. The image file may not be deleted or moved. If »bridgeTo« is set (to a host interface name, e.g. as »eth0«), it is added as bridged network "Adapter 2" (which some hosts need).
function register-vbox {( set -eu # 1: diskImages, 2?: bridgeTo
    diskImages=$1 ; bridgeTo=${2:-}
    vmName="nixos-@{config.networking.hostName}"
    VBoxManage=$( PATH=$hostPath which VBoxManage ) # The host is supposed to run these anyway, and »pkgs.virtualbox« is marked broken on »aarch64«.

    $VBoxManage createvm --name "$vmName" --register --ostype Linux26_64
    $VBoxManage modifyvm "$vmName" --memory 2048 --pae off --firmware efi

    $VBoxManage storagectl "$vmName" --name SATA --add sata --portcount 4 --bootable on --hostiocache on

    index=0 ; for decl in ${diskImages//:/ } ; do
        diskImage=${decl/*=/}
        if [[ ! -e $diskImage.vmdk ]] ; then
            $VBoxManage internalcommands createrawvmdk -filename $diskImage.vmdk -rawdisk $diskImage # pass-through
        fi
        $VBoxManage storageattach "$vmName" --storagectl SATA --port $(( index++ )) --device 0 --type hdd --medium $diskImage.vmdk
    done

    if [[ $bridgeTo ]] ; then # VBoxManage list bridgedifs
        $VBoxManage modifyvm "$vmName" --nic2 bridged --bridgeadapter2 $bridgeTo
    fi

    # TODO: The serial settings between qemu and vBox seem incompatible. With a simple »console=ttyS0«, vBox hangs on start. So just disable this for now an use qemu for headless setups. The UX here is awful anyway.
   #$VBoxManage modifyvm "$vmName" --uart1 0x3F8 4 --uartmode1 server /run/user/$(id -u)/$vmName.socket # (guest sets speed)

    set +x # avoid double-echoing
    echo '# VM info:'
    echo " VBoxManage showvminfo $vmName"
    echo '# start VM:'
    echo " VBoxManage startvm $vmName --type headless"
    echo '# kill VM:'
    echo " VBoxManage controlvm $vmName poweroff"
   #echo '# create TTY:'
   #echo " socat UNIX-CONNECT:/run/user/$(id -u)/$vmName.socket PTY,link=/run/user/$(id -u)/$vmName.pty"
   #echo '# connect TTY:'
   #echo " screen /run/user/$(id -u)/$vmName.pty"
    echo '# screenshot:'
    echo " ssh $(@{native.inetutils}/bin/hostname) VBoxManage controlvm $vmName screenshotpng /dev/stdout | display"
)}

## Runs a host in QEMU, taking the same disk specification as the installer. It infers a number of options from he target system's configuration.
#  Currently, this only works for x64 (on x64) ...
function run-qemu {( set -eu # 1: diskImages
    generic-arg-parse "$@"
    diskImages=${argv[0]}
    if [[ ${args[debug]:-} ]] ; then set -x ; fi

    qemu=( @{native.qemu_full}/bin/qemu-system-@{config.preface.hardware} )
    qemu+=( -m ${args[mem]:-2048} -smp ${args[smp]:-4} )

    if [[ @{config.preface.hardware}-linux == "@{native.system}" && ! ${args[no-kvm]:-} ]] ; then
        qemu+=( -cpu host -enable-kvm ) # For KVM to work vBox may not be running anything at the same time (and vBox hangs on start if qemu runs). Pass »--no-kvm« and accept ~10x slowdown, or stop vBox.
    elif [[ @{config.preface.hardware} == aarch64 ]] ; then # assume it's a raspberry PI (or compatible)
        # TODO: this does not work yet:
        qemu+=( -machine type=raspi3b -m 1024 ) ; args[no-nat]=1
        # ... and neither does this:
        #qemu+=( -M virt -m 1024 -smp 4 -cpu cortex-a53  ) ; args[no-nat]=1
    fi # else things are going to be quite slow

    for decl in ${diskImages//:/ } ; do
        qemu+=( -drive format=raw,file="${decl/*=/}" ) #,if=none,index=0,media=disk,id=disk0 -device "virtio-blk-pci,drive=disk0,disable-modern=on,disable-legacy=off" )
    done

    if [[ @{config.boot.loader.systemd-boot.enable} || ${args[efi]:-} ]] ; then
        qemu+=( -bios @{pkgs.OVMF.fd}/FV/OVMF.fd ) # UEFI. Otherwise it boots something much like a classic BIOS?
    fi
    if [[ @{config.preface.hardware} == aarch64 ]] ; then
        qemu+=( -kernel @{config.system.build.kernel}/Image -initrd @{config.system.build.initialRamdisk}/initrd -append "$(echo -n "@{config.boot.kernelParams[@]}")" )
    fi

    for param in "@{config.boot.kernelParams[@]}" ; do if [[ $param == 'console=ttyS0' || $param == 'console=ttyS0',* ]] ; then
        qemu+=( -nographic ) # »-nographic« by default only shows output once th system reaches the login prompt. Add »config.boot.kernelParams = [ "console=tty1" "console=ttyS0" ]« to log to serial (»-nographic«) and the display (if there is one), preferring the last »console« option for the initrd shell (if enabled and requested).
    fi ; done

    if [[ ! ${args[no-nat]:-} ]] ; then
        qemu+=( -nic user,model=virtio-net-pci ) # NATed, IPs: 10.0.2.15+/32, gateway: 10.0.2.2
    fi

    # TODO: network bridging:
    #[[ @{config.networking.hostId} =~ ^(.)(.)(.)(.)(.)(.)(.)(.)$ ]] ; mac=$( printf "52:54:%s%s:%s%s:%s%s:%s%s" "${BASH_REMATCH[@]:1}" )
    #qemu+=( -netdev bridge,id=enp0s3,macaddr=$mac -device virtio-net-pci,netdev=hn0,id=nic1 )

    # To pass a USB device (e.g. a YubiKey for unlocking), add pass »--usb-port=${bus}-${port}«, where bus and port refer to the physical USB port »/sys/bus/usb/devices/${bus}-${port}« (see »lsusb -tvv«). E.g.: »--usb-port=3-1.1.1.4«
    if [[ ${args[usb-port]:-} ]] ; then for decl in ${args[usb-port]//:/ } ; do
        qemu+=( -usb -device usb-host,hostbus="${decl/-*/}",hostport="${decl/*-/}" )
    done ; fi

    ( set -x ; "${qemu[@]}" )

    # https://askubuntu.com/questions/54814/how-can-i-ctrl-alt-f-to-get-to-a-tty-in-a-qemu-session

)}

## Creates a random static key on a new key partition on the GPT partitioned »$blockDev«. The drive can then be used as headless but removable disk unlock method.
#  To create/clear the GPT: $ sgdisk --zap-all "$blockDev"
function add-bootkey-to-keydev {( set -eu # 1: blockDev, 2?: hostHash
    blockDev=$1 ; hostHash=${2:-@{config.networking.hostName!hashString.sha256}}
    bootkeyPartlabel=bootkey-${hostHash:0:8}
    @{native.gptfdisk}/bin/sgdisk --new=0:0:+1 --change-name=0:"$bootkeyPartlabel" --typecode=0:0000 "$blockDev" # create new 1 sector (512b) partition
    @{native.parted}/bin/partprobe "$blockDev" ; @{native.systemd}/bin/udevadm settle -t 15 # wait for partitions to update
    </dev/urandom tr -dc 0-9a-f | head -c 512 >/dev/disk/by-partlabel/"$bootkeyPartlabel"
)}