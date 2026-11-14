{ inputs, ... }:
let
  subvolume = mountpoint: {
    inherit mountpoint;
    mountOptions = [ "compress=zstd:3" ];
  };
in
{
  flake.modules.nixos.pella-disko = {
    imports = [ inputs.disko.nixosModules.disko ];

    disko.devices.disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-eui.e8238fa6bf530001001b448b4fa70f16";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            priority = 1;
            size = "2G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          crypt = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              extraFormatArgs = [ "--type" "luks2" ];
              settings.crypttabExtraOpts = [ "tpm2-device=auto" ];
              content = {
                type = "btrfs";
                subvolumes = {
                  "@root" = subvolume "/";
                  "@root-blank" = {};
                  "@nix" = subvolume "/nix";
                  "@home" = subvolume "/home";
                  "@persist" = subvolume "/persist";
                  "@log" = subvolume "/var/log";
                  "@home-snapshots" = subvolume "/home/.snapshots";
                  "@persist-snapshots" = subvolume "/persist/.snapshots";
                };
                postCreateHook = ''
                  top=$(mktemp -d)
                  mount -t btrfs -o subvolid=5 "$device" "$top"
                  trap 'umount "$top"; rmdir "$top"' EXIT
                  btrfs property set -ts "$top/@root-blank" ro true
                '';
              };
            };
          };
        };
      };
    };

    fileSystems = {
      "/nix".neededForBoot = true;
      "/home".neededForBoot = true;
      "/persist".neededForBoot = true;
    };
  };
}
