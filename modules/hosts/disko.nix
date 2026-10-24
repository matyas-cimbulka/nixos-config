{ inputs, ... }:
let
  firstDisk = "/dev/disk/by-id/ata-ST4000NM0024-1HT178_Z4F0EAL2";
  secondDisk = "/dev/disk/by-id/ata-ST4000NM0024-1HT178_S4F00BRX";
  
  subvolume = mountpoint: {
    inherit mountpoint;
    mountOptions = [ "compress=zstd:6" ];
  };
in
{
  flake.modules.nixos.tycho-disko = { lib, ... }: {
    imports = [ inputs.disko.nixosModules.disko ];

    disko.devices._meta.deviceDependencies.disk.first = [ [ "disk" "second" ] ];

    disko.devices.disk = {
      first = {
        type = "disk";
        device = firstDisk;
        content = {
          type = "gpt";
          partitions = {
            bios = {
              priority = 1;
              size = "1M";
              type = "EF02";
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-L" "tycho-root" "-d" "raid1" "-m" "raid1" "${secondDisk}-part2" ];

                subvolumes = {
                  "@" = subvolume "/";
                  "@boot" = subvolume "/boot";
                  "@nix" = subvolume "/nix";
                  "@home" = subvolume "/home";
                  "@log" = subvolume "/var/log";
                  "@microvms" = subvolume "/var/lib/microvms";
                };
              };
            };
          };
        };
      };
      second = {
        type = "disk";
        device = secondDisk;
        content = {
          type = "gpt";
          partitions = {
            bios = {
              priority = 1;
              size = "1M";
              type = "EF02";
            };

            root = { size = "100%"; };
          };
        };
      };
    };

    fileSystems = lib.genAttrs [ "/" "/nix" "/home" "/var/log" "/var/lib/microvms" ] (_: {
      device = lib.mkForce "/dev/disk/by-label/tycho-root";
    });

    zramSwap = {
      enable = true;
      memoryPercent = 25;
    };

    boot.loader.grub = {
      enable = true;
      efiSupport = false;
    };
  };
}
