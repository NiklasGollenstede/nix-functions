/*

# Disk Declarations

Options to declare devices and partitions to be picked up by the installer scripts.


## Implementation

```nix
#*/# end of MarkDown, beginning of NixOS module:
dirname: inputs: { config, pkgs, lib, ... }: let inherit (inputs.self) lib; in let
    prefix = inputs.config.prefix;
    cfg = config.${prefix}.fs.disks;
in {

    options.${prefix} = { fs.disks = {
        devices = lib.mkOption {
            description = "Set of disk devices that this host will be installed on.";
            type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: { options = {
                name = lib.mkOption { description = "Name that this device is being referred to as in other places."; type = lib.types.str; default = name; readOnly = true; };
                size = lib.mkOption { description = "The size of the image to create, when using an image for this device, as argument to »fallocate -l«."; type = lib.types.str; default = "16G"; };
                serial = lib.mkOption { description = "Serial number of the specific hardware device to use. If set the device path passed to the installer must point to the device with this serial. Use »udevadm info --query=property --name=$DISK | grep -oP 'ID_SERIAL_SHORT=\K.*'« to get the serial."; type = lib.types.nullOr lib.types.str; default = null; };
                alignment = lib.mkOption { description = "Default alignment quantifier for partitions on this device. Should be at least the optimal physical write size of the device, but going larger at worst wastes this many times the number of partitions disk sectors."; type = lib.types.int; default = 16384; };
                mbrParts = lib.mkOption { description = "Up to three colon-separated (GPT) partition numbers that will be made available in a hybrid MBR."; type = lib.types.nullOr lib.types.str; default = null; };
                extraFDiskCommands = lib.mkOption { description = "»fdisk« menu commands to run against the hybrid MBR. ».mbrParts« 1[2[3]] exist as transfers from the GPT table, and part4 is the protective GPT part. Can do things like marking partitions as bootable or changing their type. Spaces and end-of-line »#«-prefixed comments are removed, new lines and »;« also mean return."; type = lib.types.lines; default = ""; example = ''
                    t;1;b  # type ; part1 ; W95 FAT32
                    a;1    # active/boot ; part1
                ''; };
            }; }));
            default = { primary = { }; };
        };
        partitions = lib.mkOption {
            description = "Set of disks disk partitions that the system will need/use. Partitions will be created on their respective ».disk«s in ».order« using »sgdisk -n X:+0+$size«.";
            type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: { options = {
                name = lib.mkOption { description = "Name/partlabel that this partition can be referred to as once created."; type = lib.types.str; default = name; readOnly = true; };
                disk = lib.mkOption { description = "Name of the disk that this partition resides on, which will automatically be declared with default options."; type = lib.types.str; default = "primary"; };
                type = lib.mkOption { description = "»gdisk« partition type of this partition."; type = lib.types.str; };
                size = lib.mkOption { description = "Partition size, either as integer suffixed with »K«, »M«, »G«, etc for sizes in XiB, or an integer suffixed with »%« for that portion of the size of the actual disk the partition gets created on. Or »null« to fill the remaining disk space."; type = lib.types.nullOr lib.types.str; default = null; };
                position = lib.mkOption { description = "Position at which to create the partition. The default »+0« means the beginning of the largest free block."; type = lib.types.str; default = "+0"; };
                alignment = lib.mkOption { description = "Adjusted alignment quantifier for this partition only."; type = lib.types.nullOr lib.types.int; default = null; example = 1; };
                index = lib.mkOption { description = "Optionally explicit partition table index to place this partition in. Use ».order« to make sure that this index hasn't been used yet.."; type = lib.types.nullOr lib.types.int; default = null; };
                order = lib.mkOption { description = "Creation order ranking of this partition. Higher orders will be created first, and will thus be placed earlier in the partition table (if ».index« isn't explicitly set) and also further to the front of the disk space."; type = lib.types.int; default = 1000; };
            }; }));
            default = { };
        };
        partitionList = lib.mkOption { description = "Partitions as a sorted list"; type = lib.types.listOf (lib.types.attrsOf lib.types.anything); default = lib.sort (before: after: before.order >= after.order) (lib.attrValues cfg.partitions); readOnly = true; internal = true; };

        # These are less disk-state-describing and more installation-imperative ...
        # Also, these are run as root and thee are no security or safety checks ...
        postPartitionCommands = lib.mkOption { description = ""; type = lib.types.lines; default = ""; };
        postFormatCommands = lib.mkOption { description = ""; type = lib.types.lines; default = ""; };
        postMountCommands = lib.mkOption { description = ""; type = lib.types.lines; default = ""; };
        initSystemCommands = lib.mkOption { description = ""; type = lib.types.lines; default = ""; };
        restoreSystemCommands = lib.mkOption { description = ""; type = lib.types.lines; default = ""; };
    }; };

    # Create all devices referenced by partitions:
    config.${prefix}.fs.disks.devices = lib.wip.mapMerge (name: { ${name} = { }; }) (lib.catAttrs "disk" config.${prefix}.fs.disks.partitionList);

}