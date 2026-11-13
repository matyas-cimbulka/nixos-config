{ inputs, config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check failsEvaluation;
  modules = config.flake.modules.nixos;
  selected = [ inputs.microvm.nixosModules.microvm modules.microvm-guest ];
  active = mkSystem selected { deployment.microvm.interfaceName = "lan0"; };
  renamed = extend active { deployment.microvm.interfaceName = lib.mkForce "guest0"; };
  ssh = extend active { services.openssh.enable = true; };
  noKeygen = extend ssh { services.openssh.generateHostKeys = false; };
  missingInterface = mkSystem selected {};
  volumes = active.config.microvm.volumes;
  shares = active.config.microvm.shares;
in
{
  flake.lib.compositionTests.microvm-platform = {
    interface-name-has-one-source = check "MicroVM interface renaming and network matching should use the deployment name."
      (renamed.config.systemd.network.links."10-lan".linkConfig.Name == "guest0"
        && renamed.config.systemd.network.networks.lan.matchConfig.Name == "guest0");
    interface-name-is-mandatory = check "MicroVM platform should require its deployment interface name."
      (failsEvaluation missingInterface.config.systemd.network.links."10-lan".linkConfig.Name);
    default-guest-networking = check "MicroVM networking should use networkd and its explicit DHCP network."
      (active.config.systemd.network.enable && !active.config.networking.useDHCP
        && active.config.systemd.network.networks.lan.networkConfig.DHCP == "ipv4");
    persists-host-identity = check "MicroVM SSH host identity should have its own persistent volume."
      (lib.any (volume: volume.mountPoint == "/var/lib/ssh" && volume.image == "ssh-host-keys.img") volumes);
    keeps-debugging-homes-ephemeral = check "MicroVM platform should add no user-home volume or host-home share."
      (lib.all (volume: !(lib.hasPrefix "/home" volume.mountPoint)) volumes
        && lib.all (share: !(lib.hasPrefix "/home" share.source)) shares);
    shares-only-read-only-store = check "MicroVM store sharing should use the read-only store destination."
      (lib.any (share: share.source == "/nix/store" && share.mountPoint == "/nix/.ro-store" && share.proto == "virtiofs") shares);
    ssh-key-paths-and-mount-order-compose = check "Enabled SSH should keep host keys on the identity volume and wait for its mount."
      (lib.all (key: lib.hasPrefix "/var/lib/ssh/" key.path) ssh.config.services.openssh.hostKeys
        && builtins.elem "/var/lib/ssh" ssh.config.systemd.services.sshd.unitConfig.RequiresMountsFor
        && builtins.elem "/var/lib/ssh" ssh.config.systemd.services.sshd-keygen.unitConfig.RequiresMountsFor);
    disabled-ssh-has-no-support = check "The MicroVM platform alone should not enable SSH or create SSH units."
      (!active.config.services.openssh.enable && !(active.config.systemd.services ? sshd)
        && !(active.config.systemd.services ? sshd-keygen));
    disabling-keygen-removes-keygen-support = check "Disabling SSH host-key generation should remove its unit contribution."
      (!(noKeygen.config.systemd.services ? sshd-keygen));
  };
}
