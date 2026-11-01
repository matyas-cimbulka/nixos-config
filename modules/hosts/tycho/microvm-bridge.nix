{
  flake.modules.nixos.tycho-microvm-bridge = {
    systemd.network = {
      netdevs.microvm-br.netdevConfig = {
        Kind = "bridge";
        Name = "microvm-br";
      };

      networks = {
        microvm-br = {
          matchConfig.Name = "microvm-br";

          addresses = [
            {
              addressConfig.Address = "10.77.0.1/24";
            }
          ];
        };

        microvm-tap = {
          matchConfig.Name = "vm-*";
          networkConfig.Bridge = "microvm-br";
        };
      };
    };

    networking = {
      nat = {
        enable = true;

        externalInterface = "wan0";
        internalInterfaces = [ "microvm-br" ];
      };

      firewall.interfaces."microvm-br" = {
        allowedUDPPorts = [ 53 67 ];
        allowedTCPPorts = [ 53 ];
      };
    };

    services = {
      resolved.enable = false;

      dnsmasq = {
        enable = true;

        resolveLocalQueries = true;

        settings = {
          interface = [ "microvm-br" ];
          bind-dynamic = true;

          dhcp-range = [ "10.77.0.10,10.77.0.254,255.255.255.0,12h" ];
          dhcp-option = [
            "option:router,10.77.0.1"
            "option:dns-server,10.77.0.1"
            "option:domain-name"
          ];

          domain = "internal.cimbulka.net";
          local = "/internal.cimbulka.net/";

          dhcp-fqdn = true;
          domain-needed = true;
          no-hosts = true;

          no-resolv = true;
          server = [
            "1.1.1.1"
            "1.0.0.1"
          ];
        };
      };

      tailscale.extraSetFlags = [
        "--accept-dns=false"
      ];
    };
  };
}
