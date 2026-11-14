{ inputs, ... }:
{
  flake.modules.nixos.ephemeral-root = { config, lib, pkgs, utils, ... }:
  let
    cfg = config.deployment.ephemeralRoot;
    deviceUnit = "${utils.escapeSystemdPath cfg.device}.device";
  in
  {
    imports = [ inputs.impermanence.nixosModules.impermanence ];

    options.deployment.ephemeralRoot = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Recreate the Btrfs root from a read-only blank subvolume before mounting it.";
      };
      device = lib.mkOption {
        type = lib.types.strMatching "/dev/.*";
        default = throw "Set deployment.ephemeralRoot.device to the decrypted Btrfs device.";
        description = "Btrfs device containing the root and blank subvolumes.";
      };
      rootSubvolume = lib.mkOption {
        type = lib.types.strMatching "@[A-Za-z0-9_-]+";
        default = "@root";
        description = "Top-level Btrfs subvolume to replace at boot.";
      };
      blankSubvolume = lib.mkOption {
        type = lib.types.strMatching "@[A-Za-z0-9_-]+";
        default = "@root-blank";
        description = "Read-only, empty Btrfs subvolume used as the root baseline.";
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.rootSubvolume != cfg.blankSubvolume;
          message = "Ephemeral root and its read-only baseline must be different subvolumes.";
        }
        {
          assertion = config.fileSystems."/".fsType == "btrfs"
            && config.fileSystems."/".device == cfg.device
            && builtins.elem "subvol=${cfg.rootSubvolume}" config.fileSystems."/".options;
          message = "Ephemeral root requires / to mount the selected Btrfs device and root subvolume.";
        }
      ];

      boot.initrd = {
        supportedFilesystems = [ "btrfs" ];
        systemd.services.reset-root = {
          description = "Recreate ephemeral Btrfs root";
          requiredBy = [ "sysroot.mount" ];
          before = [ "sysroot.mount" ];
          after = [ deviceUnit "initrd-root-device.target" "systemd-hibernate-resume.service" ];
          requires = [ deviceUnit ];
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [ pkgs.btrfs-progs pkgs.util-linux pkgs.coreutils pkgs.gnugrep ];
          script = ''
            set -euo pipefail
            top=$(mktemp -d /run/ephemeral-root.XXXXXX)
            mount -t btrfs -o subvolid=5 ${lib.escapeShellArg cfg.device} "$top"
            trap 'umount "$top"; rmdir "$top"' EXIT
            root="$top"/${lib.escapeShellArg cfg.rootSubvolume}
            blank="$top"/${lib.escapeShellArg cfg.blankSubvolume}
            next="$root.new"

            # Validate the baseline before touching the current root.
            btrfs subvolume show "$blank" >/dev/null
            btrfs property get -ts "$blank" ro | grep -qx 'ro=true'
            if [ -e "$root" ]; then
              btrfs subvolume show "$root" >/dev/null
            fi
            if [ -e "$next" ]; then
              btrfs subvolume show "$next" >/dev/null
              btrfs subvolume delete --recursive -- "$next"
            fi
            btrfs subvolume snapshot "$blank" "$next"
            if [ -e "$root" ]; then
              btrfs subvolume delete --recursive -- "$root"
            fi
            mv -- "$next" "$root"
          '';
        };
      };
    };
  };
}
