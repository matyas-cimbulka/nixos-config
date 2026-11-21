{ config, lib, deploymentHelpers, ... }:
let
  inherit (deploymentHelpers) check;
  pella = config.flake.nixosConfigurations.pella;
  machine = pella.config;
  disk = machine.disko.devices.disk.main or {};
  encrypted = disk.content.partitions.crypt.content or {};
  subvolumes = encrypted.content.subvolumes or {};
  mounts = {
    "@root" = "/";
    "@nix" = "/nix";
    "@home" = "/home";
    "@persist" = "/persist";
    "@log" = "/var/log";
    "@home-snapshots" = "/home/.snapshots";
    "@persist-snapshots" = "/persist/.snapshots";
  };
  persistence = machine.environment.persistence."/persist" or {};
  persistentDirectories = map (entry: if builtins.isString entry then entry else entry.directory)
    (persistence.directories or []);
  persistentFiles = map (entry: if builtins.isString entry then entry else entry.file)
    (persistence.files or []);
  persistsDirectory = path: lib.any
    (directory: directory == path || lib.hasPrefix "${directory}/" path) persistentDirectories;
  homeSnapshots = machine.services.snapper.configs.home or {};
  systemSnapshots = machine.services.snapper.configs.persist or {};
  reset = machine.boot.initrd.systemd.services.reset-root or {};
  home = machine.home-manager.users.matyas;
  identity = { name = "Matyas Cimbulka"; email = "matyas.cimbulka@gmail.com"; };
  publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHuanqwyg+nSluVQKYa5CsEmxjJLW5JKQosV2D7h1rKP";
in
{
  flake.lib.deploymentTests.pella = {
    personal-vcs-identity-and-signing-key = check "Pella and the standalone workstation home must use Matyas's supplied VCS identity and public signing key."
      ((home.programs.git.settings.user or {}) == identity
        && (home.programs.jujutsu.settings.user or {}) == identity
        && (home.home.file.".ssh/signing.pub".text or "") == "${publicKey}\n"
        && home.programs.git.signing.allowedSigners == "${identity.email} namespaces=\"git\" ${publicKey}\n"
        && config.flake.homeConfigurations.matyas-workstation.config.programs.git.settings.user == identity
        && config.flake.homeConfigurations.matyas-workstation.config.programs.jujutsu.settings.user == identity);
    personal-tailscale-enrollment = check "Pella should join as a personal device through interactive login and preserve its client state."
      (machine.services.tailscale.enable && machine.deployment.tailscale.enrollment == "interactive"
        && machine.services.tailscale.authKeyFile == null && machine.services.tailscale.extraUpFlags == []
        && !(machine.systemd.services ? tailscaled-autoconnect)
        && persistsDirectory "/var/lib/tailscale");
    greeter-state-survives-root-reset = check "Pella should preserve greeter appearance and AccountsService metadata across root reset."
      (machine.services.displayManager.noctalia-greeter.enable
        && lib.all persistsDirectory [ "/var/lib/noctalia-greeter" "/var/lib/AccountsService" ]);
    keyring-state-is-covered-by-home-persistence = check "Pella's desktop keyring data must live beneath the independently persistent user home."
      (machine.services.gnome.gnome-keyring.enable
        && machine.home-manager.users.matyas.home.homeDirectory == "/home/matyas"
        && lib.hasPrefix "/home/matyas/" machine.home-manager.users.matyas.xdg.dataHome
        && machine.fileSystems."/home".fsType == "btrfs"
        && builtins.elem "subvol=@home" machine.fileSystems."/home".options
        && machine.fileSystems."/home".neededForBoot);
    identity-and-platform = check "Pella must be the x86_64 workstation in Europe/Prague."
      (machine.networking.hostName == "pella" && machine.time.timeZone == "Europe/Prague"
        && machine.nixpkgs.hostPlatform.system == "x86_64-linux");
    uses-own-hardware-report = check "Pella must use its own hardware report without Facter DHCP overriding NetworkManager."
      (toString machine.hardware.facter.reportPath == toString ../../modules/hosts/pella/facter.json
        && !machine.hardware.facter.detected.dhcp.enable
        && machine.networking.networkmanager.enable && !machine.networking.useNetworkd);
    receives-workstation-home = check "Pella must select Matyas's workstation account and Home Manager environment."
      (machine.users.users.matyas.isNormalUser
        && builtins.elem "networkmanager" machine.users.users.matyas.extraGroups
        && machine.home-manager.users.matyas.programs.neovim.enable
        && machine.home-manager.users.matyas.programs.btop.enable);
    storage-target-is-explicit = check "Pella's disk layout must target the reported WD SN7100 by its stable identity."
      ((disk.device or null) == "/dev/disk/by-id/nvme-eui.e8238fa6bf530001001b448b4fa70f16"
        && (disk.content.type or null) == "gpt");
    encrypted-btrfs-and-efi = check "Pella must have a 2 GiB EFI partition and LUKS2-encrypted Btrfs data."
      ((disk.content.partitions.ESP.size or null) == "2G"
        && (disk.content.partitions.ESP.content.format or null) == "vfat"
        && (encrypted.type or null) == "luks"
        && builtins.elem "--type" (encrypted.extraFormatArgs or [])
        && builtins.elem "luks2" (encrypted.extraFormatArgs or [])
        && (encrypted.content.type or null) == "btrfs");
    independent-persistent-subvolumes = check "Root, Nix, home, state, logs, and snapshot stores must have independent Btrfs subvolumes."
      (lib.all (name: (subvolumes.${name}.mountpoint or null) == mounts.${name}) (builtins.attrNames mounts)
        && subvolumes ? "@root-blank" && (subvolumes."@root-blank".mountpoint or null) == null
        && lib.all (mount: (machine.fileSystems.${mount}.fsType or null) == "btrfs") (builtins.attrValues mounts));
    compression-and-early-persistence = check "Data must use zstd:3 and persistence must be mounted before boot-time consumers."
      (lib.all (mount: builtins.elem "compress=zstd:3" (machine.fileSystems.${mount}.options or []))
        (builtins.attrValues mounts)
        && (machine.fileSystems."/persist".neededForBoot or false)
        && (machine.fileSystems."/home".neededForBoot or false));
    machine-identity-and-network-state-persist = check "Machine identity, account allocation, NetworkManager, and boot security state must survive root reset."
      (builtins.elem "/etc/machine-id" persistentFiles
        && (machine.networking.networkmanager.settings.keyfile.path or null) == "/var/lib/NetworkManager/system-connections"
        && lib.all persistsDirectory
          [ "/var/lib/nixos" "/var/lib/NetworkManager" "/var/lib/sbctl" "/var/lib/systemd" "/var/lib/pcrlock.d" ]);
    login-secret-stays-runtime-only = check "Pella must recreate its local account from a password hash on encrypted persistent storage."
      (!machine.users.mutableUsers
        && machine.users.users.matyas.hashedPasswordFile == "/persist/secrets/matyas-password"
        && machine.users.users.matyas.hashedPassword == null
        && machine.users.users.matyas.initialPassword == null);
    root-reset-precedes-root-mount = check "Root reset must wait for decrypted storage and complete before mounting root."
      (builtins.elem "sysroot.mount" (reset.before or [])
        && builtins.elem "dev-mapper-cryptroot.device" (reset.after or [])
        && builtins.elem "dev-mapper-cryptroot.device" (reset.requires or [])
        && builtins.elem "sysroot.mount" (reset.requiredBy or []));
    zram-without-disk-swap = check "Pella must use zstd-compressed zram with 50% logical capacity and no disk swap or hibernation."
      (machine.zramSwap.enable && machine.zramSwap.algorithm == "zstd"
        && machine.zramSwap.memoryPercent == 50 && machine.swapDevices == []
        && (machine.systemd.sleep.settings.Sleep.AllowHibernation or true) == false);
    local-home-recovery-policy = check "Home snapshots must retain the agreed hourly, daily, weekly, and monthly history."
      ((homeSnapshots.SUBVOLUME or null) == "/home"
        && (homeSnapshots.TIMELINE_CREATE or false) && (homeSnapshots.TIMELINE_CLEANUP or false)
        && (homeSnapshots.TIMELINE_LIMIT_HOURLY or null) == 24
        && (homeSnapshots.TIMELINE_LIMIT_DAILY or null) == 7
        && (homeSnapshots.TIMELINE_LIMIT_WEEKLY or null) == 4
        && (homeSnapshots.TIMELINE_LIMIT_MONTHLY or null) == 3
        && (homeSnapshots.ALLOW_USERS or []) == [ "matyas" ]);
    local-system-recovery-policy = check "Persistent system state must have daily snapshots with root-only access and weekly retention."
      ((systemSnapshots.SUBVOLUME or null) == "/persist"
        && (systemSnapshots.TIMELINE_CLEANUP or false)
        && (systemSnapshots.TIMELINE_LIMIT_DAILY or null) == 7
        && (systemSnapshots.TIMELINE_LIMIT_WEEKLY or null) == 4
        && (systemSnapshots.ALLOW_USERS or []) == []
        && (machine.systemd.timers.snapper-persist.timerConfig.OnCalendar or null) == "daily"
        && !(machine.services.snapper.configs ? root));
    signed-measured-boot-and-tpm-unlock = check "Pella must sign and measure boot artifacts and request TPM2 disk unlocking."
      ((machine.boot.lanzaboote.enable or false) && (machine.boot.lanzaboote.measuredBoot.enable or false)
        && machine.boot.lanzaboote.measuredBoot.pcrlockDirectory == "/var/lib/pcrlock.d"
        && builtins.elem "/var/lib/pcrlock.d"
          (machine.systemd.services.systemd-pcrlock-firmware-code.unitConfig.RequiresMountsFor or [])
        && builtins.elem "tpm2-device=auto" (machine.boot.initrd.luks.devices.cryptroot.crypttabExtraOpts or [])
        && !(machine.boot.loader.systemd-boot.enable or false));
    system-evaluates = builtins.deepSeq pella.config.system.build.toplevel.drvPath true;
  };
}
