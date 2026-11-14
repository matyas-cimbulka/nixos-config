{ inputs, config, lib, ... }:
let
  pella = config.flake.nixosConfigurations.pella;
  targetSystem = pella.config.nixpkgs.hostPlatform.system;
in
{
  perSystem = { pkgs, system, ... }: {
    checks = lib.optionalAttrs (system == targetSystem) {
      runtime-pella-storage = (pkgs.callPackage "${inputs.disko}/lib" {
        makeTest = import "${inputs.nixpkgs}/nixos/tests/make-test-python.nix";
        eval-config = import "${inputs.nixpkgs}/nixos/lib/eval-config.nix";
        qemu-common = import "${inputs.nixpkgs}/nixos/lib/qemu-common.nix";
      }).testLib.makeDiskoTest {
        inherit pkgs;
        name = "pella-storage";
        extendModules = pella.extendModules;
        disko-config.disko.devices = lib.recursiveUpdate pella.config.disko.devices {
          disk.main.content.partitions.crypt.content = {
            # Test-only key and work factor for the small disposable VM.
            askPassword = false;
            settings.keyFile = "/tmp/secret.key";
            extraFormatArgs = pella.config.disko.devices.disk.main.content.partitions.crypt.content.extraFormatArgs
              ++ [ "--pbkdf-memory" "65536" ];
          };
        };
        extraInstallerConfig.virtualisation = {
          memorySize = 2048;
          emptyDiskImages = lib.mkForce [ 8192 ];
        };
        extraSystemConfig = {
          nixpkgs.hostPlatform = "x86_64-linux";
          hardware.facter.reportPath = lib.mkForce null;
          boot = {
            lanzaboote = {
              enable = lib.mkForce false;
              measuredBoot.enable = lib.mkForce false;
            };
            loader = {
              systemd-boot.enable = lib.mkOverride 49 true;
              efi.canTouchEfiVariables = lib.mkForce false;
            };
            initrd.luks.devices.cryptroot = {
              keyFile = lib.mkForce "/tmp/secret.key";
              crypttabExtraOpts = lib.mkForce [];
            };
            # Disko's extendModules path does not inject its standalone initrd key.
            initrd.secrets."/tmp/secret.key" = pkgs.writeText "pella-vm-luks-key" "secretsecret";
          };
          security.tpm2.enable = lib.mkForce false;
          # The helper shares an immutable 9p store; HM activation needs a writable daemon store.
          systemd.services.home-manager-matyas.enable = lib.mkForce false;
          users.users.matyas = {
            hashedPasswordFile = lib.mkForce null;
            initialPassword = "test-only";
          };
          # Accelerate age-based cleanup while retaining the production count policy.
          services.snapper.configs.home.TIMELINE_MIN_AGE = 0;
        };
        extraTestScript = ''
          machine.wait_for_unit("multi-user.target")
          machine.succeed("cryptsetup isLuks /dev/vda2")
          machine.succeed("findmnt -rn -o FSTYPE / | grep -qx btrfs")
          machine.succeed("findmnt -rn -o OPTIONS / | grep -q compress=zstd:3")
          machine.succeed("btrfs subvolume list / | grep -q 'path @root-blank$'")
          machine.succeed("swapon --show=NAME --noheadings | grep -q '^/dev/zram'")

          with subtest("local snapshot recovery"):
              machine.succeed("echo original > /home/matyas/recovery-test")
              snapshot = machine.succeed("snapper --no-dbus -c home create --print-number").strip()
              machine.succeed("echo changed > /home/matyas/recovery-test")
              machine.succeed(f"cp /home/.snapshots/{snapshot}/snapshot/matyas/recovery-test /home/matyas/recovery-test")
              machine.succeed("grep -qx original /home/matyas/recovery-test")
              machine.succeed("systemctl start snapper-persist.service")
              machine.succeed("snapper --no-dbus -c persist list | grep -q daily")
              machine.succeed("test $(stat -c %a /persist/.snapshots) = 700")

          with subtest("root reset preserves sibling subvolumes and identity"):
              identity = machine.succeed("cat /etc/machine-id").strip()
              machine.wait_for_unit("NetworkManager.service")
              machine.succeed("nmcli connection add type ethernet con-name persistence-test ifname absent0 autoconnect no")
              connection = machine.succeed("nmcli -g connection.uuid connection show persistence-test").strip()
              machine.succeed("test -n \"$(ls -A /var/lib/NetworkManager/system-connections)\"")
              machine.succeed("echo home > /home/matyas/persistent-marker")
              machine.succeed("echo state > /var/lib/nixos/persistent-marker")
              machine.succeed("echo nix > /nix/persistent-marker")
              machine.succeed("echo log > /var/log/persistent-marker")
              machine.succeed("touch /root/volatile-marker")
              machine.succeed("mkdir -p /var/lib/machines; btrfs subvolume create /var/lib/machines/volatile-child")
              machine.succeed("sync")
              # Disko's custom QEMU command exits on reboot; power-cycle the same disk.
              machine.shutdown()
              machine.start()
              machine.wait_for_unit("multi-user.target")
              machine.fail("test -e /root/volatile-marker")
              machine.fail("test -e /var/lib/machines/volatile-child")
              machine.succeed("grep -qx home /home/matyas/persistent-marker")
              machine.succeed("grep -qx state /var/lib/nixos/persistent-marker")
              machine.succeed("grep -qx nix /nix/persistent-marker")
              machine.succeed("grep -qx log /var/log/persistent-marker")
              assert machine.succeed("cat /etc/machine-id").strip() == identity
              machine.wait_for_unit("NetworkManager.service")
              assert machine.succeed("nmcli -g connection.uuid connection show persistence-test").strip() == connection
              machine.succeed(f"test -f /home/.snapshots/{snapshot}/snapshot/matyas/recovery-test")

          with subtest("snapshot cleanup preserves live data and recovery history"):
              machine.succeed("for i in $(seq 1 30); do snapper --no-dbus -c home create --cleanup-algorithm timeline; done")
              machine.succeed("snapper --no-dbus -c home cleanup timeline")
              machine.succeed("test $(find /home/.snapshots -mindepth 1 -maxdepth 1 -type d | wc -l) -lt 30")
              machine.succeed("grep -qx home /home/matyas/persistent-marker")
              machine.succeed(f"test -f /home/.snapshots/{snapshot}/snapshot/matyas/recovery-test")
        '';
      };
    };
  };
}
