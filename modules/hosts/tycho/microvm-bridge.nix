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

    networking.nat = {
      enable = true;

      externalInterface = "enp0s31f6";
      internalInterfaces = [ "microvm-br" ];
    };
  };
}