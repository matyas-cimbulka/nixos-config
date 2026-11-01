{
  flake.modules.nixos.tailscale-dns = { lib, ... }: {
    networking.firewall.interfaces = {
      "tailscale0" = {
        allowedUDPPorts = [ 53 ];
        allowedTCPPorts = [ 53 ];
      };

      "lan0".allowedTCPPorts = [ 80 443];
    };

    environment.etc."resolv.conf".source =
      lib.mkForce "/run/systemd/resolve/resolv.conf";

    services = {
      tailscale.extraSetFlags = [
        "--accept-dns=false"
      ];

      resolved.settings.Resolve.DNSStubListener = false;

      blocky = {
        enable = true;

        settings = {
          upstreams = {
            init.strategy = "fast";

            groups.default = [
              "1.1.1.1"
              "1.0.0.1"
            ];

            strategy = "parallel_best";
            timeout = "2s";
          };

          connectIPVersion = "v4";

          customDNS = {
            customTTL = "1h";
            filterUnmappedTypes = true;

            mapping."cimbulka.net" = "100.119.128.83";

            zone = ''
              internal.cimbulka.net. 300 IN TXT "bridge-only"
            '';
          };

          blocking = {
            denylists = {
              ads = [
                "https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt"
                "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
                "http://sysctl.org/cameleon/hosts"
                "https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt"
              ];

              special = [
                "https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/fakenews/hosts"
              ];
            };

            clientGroupsBlock = {
              default = [ "ads" "special" ];
            };

            blockType = "zeroIp";
          };

          caching = {
            minTime = "2m";
            maxTime = "30m";

            prefetching = true;
            prefetchExpires = "2h";
          };

          prometheus.enable = true;

          ports = {
            http = 80;
            https = 443;
          };

          fqdnOnly.enable = true;
        };
      };
    };
  };
}