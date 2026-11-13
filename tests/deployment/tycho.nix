{ config, deploymentHelpers, lib, ... }:
let
  inherit (deploymentHelpers) host guest check sameMembers bridgeName bridgeAddress internalDomain;
  tycho = config.flake.nixosConfigurations.tycho;
  guests = host.microvm.vms;
  names = builtins.attrNames guests;
  taps = lib.concatMap (name: lib.filter (interface: interface.type == "tap") (guest name).microvm.interfaces) names;
  wanName = host.systemd.network.links."10-wan".linkConfig.Name;
in
{
  flake.lib.deploymentTests = {
    tycho = {
      evaluates = builtins.deepSeq tycho.config.system.build.toplevel.drvPath true;
      standalone-home-evaluates = builtins.deepSeq config.flake.homeConfigurations.matyas-server.activationPackage.drvPath true;
      expected-guests-are-registered = check "Tycho must register Anderson, Behemoth, and Thoth."
        (sameMembers names [ "anderson" "behemoth" "thoth" ]);
      guest-identities-match-registration = check "Guest hostnames and TAP identities must agree with Tycho's VM registration."
        (lib.all (name: (guest name).networking.hostName == name
          && lib.any (interface: interface.type == "tap" && interface.id == "vm-${name}") (guest name).microvm.interfaces) names);
      taps-attach-to-configured-bridge = check "Every guest TAP must match the host bridge attachment rule."
        (host.systemd.network.netdevs.microvm-br.netdevConfig.Kind == "bridge"
          && builtins.elem "vm-*" (lib.toList host.systemd.network.networks.microvm-tap.matchConfig.Name)
          && lib.toList host.systemd.network.networks.microvm-tap.networkConfig.Bridge == [ bridgeName ]
          && lib.all (interface: lib.hasPrefix "vm-" interface.id) taps);
      tap-addresses-are-unique = check "Guest TAP interfaces must have unique MAC addresses."
        (builtins.length taps == builtins.length (lib.unique (map (interface: interface.mac) taps)));
      bridge-dns-and-router-match-network = check "Guest DHCP must advertise the actual bridge as router and DNS server."
        (host.services.dnsmasq.enable
          && builtins.elem bridgeName host.services.dnsmasq.settings.interface
          && builtins.elem "option:router,${bridgeAddress}" host.services.dnsmasq.settings.dhcp-option
          && builtins.elem "option:dns-server,${bridgeAddress}" host.services.dnsmasq.settings.dhcp-option);
      nat-follows-interface-names = check "Guest NAT must use the declared WAN link and MicroVM bridge."
        (host.networking.nat.enable && host.networking.nat.externalInterface == wanName
          && builtins.elem bridgeName host.networking.nat.internalInterfaces);
      guest-domain-routing-follows-host-dns = check "Every guest must route the host's internal DNS domain through its LAN network."
        (lib.all (name: builtins.elem "~${internalDomain}"
          (guest name).systemd.network.networks.lan.domains) names);
      vm-startup-orders-after-dns = check "The host VM service template must require and start after internal DNS/DHCP."
        (builtins.elem "dnsmasq.service" host.systemd.services."microvm@".requires
          && builtins.elem "dnsmasq.service" host.systemd.services."microvm@".after);
      host-tailscale-uses-deployment-secret = check "Tycho's own Tailscale enrollment must use its SOPS secret and wait for secret preparation."
        (host.services.tailscale.authKeyFile == host.sops.secrets.tailscale-server-oauth.path
          && builtins.elem "sops-install-secrets.service" host.systemd.services.tailscaled-autoconnect.requires
          && builtins.elem "sops-install-secrets.service" host.systemd.services.tailscaled-autoconnect.after);
      guest-debugging-homes-stay-ephemeral = check "The deployed guests must retain Matyas tools without home-directory persistence or host-home sharing."
        (lib.all (name: let machine = guest name; in
          machine.users.users.matyas.isNormalUser
          && machine.home-manager.users.matyas.programs.btop.enable
          && lib.all (volume: !(lib.hasPrefix "/home" volume.mountPoint)) machine.microvm.volumes
          && lib.all (share: !(lib.hasPrefix "/home" share.source)) machine.microvm.shares) names);
    };
    guests = lib.mapAttrs (_: vm:
      builtins.deepSeq vm.config.config.system.build.toplevel.drvPath true
    ) guests;
  };
}
