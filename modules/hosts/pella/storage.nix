{ inputs, ... }:
{
  flake.modules.nixos.pella-storage = { config, lib, pkgs, ... }:
  let
    passwordFile = config.users.users.matyas.hashedPasswordFile;
  in
  {
    imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

    deployment.ephemeralRoot.device = "/dev/mapper/cryptroot";

    boot = {
      loader = {
        systemd-boot.enable = lib.mkForce false;
        efi = {
          canTouchEfiVariables = true;
          efiSysMountPoint = "/boot";
        };
      };
      lanzaboote = {
        enable = true;
        pkiBundle = "/var/lib/sbctl";
        allowUnsigned = false;
        configurationLimit = 4;
        measuredBoot = {
          enable = true;
          pcrs = [ 0 4 7 ];
        };
      };
      kernelParams = [ "noresume" ];
    };
    security.tpm2.enable = true;
    networking.networkmanager.settings.keyfile.path = "/var/lib/NetworkManager/system-connections";

    users = {
      mutableUsers = false;
      users.matyas.hashedPasswordFile = "/persist/secrets/matyas-password";
    };

    environment.persistence."/persist" = {
      hideMounts = true;
      directories = [
        "/var/lib/nixos"
        { directory = "/var/lib/NetworkManager"; mode = "0700"; }
        { directory = "/var/lib/sbctl"; mode = "0700"; }
        "/var/lib/systemd"
      ]
      ++ lib.optional config.boot.lanzaboote.measuredBoot.enable { directory = "/var/lib/pcrlock.d"; mode = "0700"; }
      ++ lib.optional config.hardware.bluetooth.enable { directory = "/var/lib/bluetooth"; mode = "0700"; }
      ++ lib.optional config.services.tailscale.enable { directory = "/var/lib/tailscale"; mode = "0700"; };
      files = [ "/etc/machine-id" ];
    };

    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 50;
    };

    services = {
      btrfs.autoScrub.enable = true;
      fstrim.enable = true;
      journald.settings.Journal = {
        Storage = "persistent";
        SystemMaxUse = "1G";
        MaxRetentionSec = "30day";
      };
      snapper = {
        persistentTimer = true;
        configs = {
          home = {
            SUBVOLUME = "/home";
            ALLOW_USERS = [ "matyas" ];
            SYNC_ACL = true;
            TIMELINE_CREATE = true;
            TIMELINE_CLEANUP = true;
            TIMELINE_LIMIT_HOURLY = 24;
            TIMELINE_LIMIT_DAILY = 7;
            TIMELINE_LIMIT_WEEKLY = 4;
            TIMELINE_LIMIT_MONTHLY = 3;
            TIMELINE_LIMIT_YEARLY = 0;
          };
          persist = {
            SUBVOLUME = "/persist";
            TIMELINE_CLEANUP = true;
            TIMELINE_LIMIT_HOURLY = 0;
            TIMELINE_LIMIT_DAILY = 7;
            TIMELINE_LIMIT_WEEKLY = 4;
            TIMELINE_LIMIT_MONTHLY = 0;
            TIMELINE_LIMIT_YEARLY = 0;
          };
        };
      };
    };

    systemd = {
      tmpfiles.rules = [
        "d /persist 0700 root root -"
        "d /persist/secrets 0700 root root -"
        "d /persist/.snapshots 0700 root root -"
        "d /home/.snapshots 0750 root root -"
      ];
      sleep.settings.Sleep = {
        AllowHibernation = false;
        AllowHybridSleep = false;
        AllowSuspendThenHibernate = false;
      };
      services = lib.mkMerge [
        {
          snapper-persist = {
            description = "Snapshot persistent system state";
            requires = [ "local-fs.target" ];
            after = [ "local-fs.target" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${pkgs.snapper}/bin/snapper --no-dbus -c persist create --cleanup-algorithm timeline --description daily";
            };
          };
        }
        (lib.mkIf config.boot.lanzaboote.measuredBoot.enable (lib.genAttrs [
          "systemd-pcrlock-firmware-code"
          "systemd-pcrlock-secureboot-policy"
          "systemd-pcrlock-secureboot-authority"
        ] (_: {
          unitConfig.RequiresMountsFor = [ "/var/lib/pcrlock.d" "/var/lib/systemd" ];
        })))
      ];
      timers.snapper-persist = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };
    };

    system.activationScripts = lib.mkIf (passwordFile != null) {
      pella-login-secret = {
        deps = [ "specialfs" ];
        text = ''
          if [ ! -s ${lib.escapeShellArg passwordFile} ]; then
            echo 'Provision the Matyas password hash on /persist before activating pella.' >&2
            exit 1
          fi
        '';
      };
      users.deps = [ "pella-login-secret" ];
    };
  };
}
