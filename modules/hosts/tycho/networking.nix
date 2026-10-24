{
  flake.modules.nixos.tycho-network = {
    networking = {
      nameservers = [
        "1.1.1.1"
        "1.0.0.1"
      ];

      useDHCP = false;
    };

    systemd.network.networks.wan = {
      matchConfig.PermanentMACAddress = "90:1b:0e:fc:ee:3d";
      address = [
        "188.40.66.246/32"
      ];

      routes = [
        {
          Gateway = "188.40.66.193";
          GatewayOnLink = true;
        }
      ];

      DHCP = "no";
    };
  };
}
