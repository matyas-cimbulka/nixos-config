{
  flake.modules.nixos.internal-dns = {
    networking.firewall = {
      allowedUDPPorts = [ 53 67 ];
      allowedTCPPorts = [ 53 ];
    };

    services = {
      resolved.enable = false;

      dnsmasq = {
        enable = true;

        settings = {
          dhcp-range = [ "10.77.0.10,10.77.0.254,255.255.255.0,12h" ];
          dhcp-option = [
            "option:router,10.77.0.1"
            "option:dns-server,10.77.0.2"
          ];
          domain = "internal.cimbulka.net";
          local = "/internal.cimbulka.net/";
          no-resolv = true;
          server = [
            "1.1.1.1"
            "1.0.0.1"
          ];
        };
      };
    };
  };
}