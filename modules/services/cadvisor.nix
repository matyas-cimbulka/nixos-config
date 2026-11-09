{
  flake.modules.nixos.cadvisor = { config, lib, ... }: {
    options.deployment.cadvisor = {
      overrideIntegration = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Disable cAdvisor integration for Docker and Grafana Alloy.";
      };

      metricsInterface = lib.mkOption {
        type = lib.types.str;
        description = "Network interface on which to allow access to cAdvisor metrics.";
      };
    };

    config = lib.mkIf (!config.deployment.cadvisor.overrideIntegration) (
      lib.mkMerge [
        {
          services.cadvisor.enable = lib.mkDefault true;
        }

        (lib.mkIf config.services.cadvisor.enable {
          assertions = [
            {
              assertion = config.virtualisation.docker.enable;
              message = "The cAdvisor feature requires Docker.";
            }
          ];

          networking.firewall.interfaces.${config.deployment.cadvisor.metricsInterface}.allowedTCPPorts = [
            config.services.cadvisor.port
          ];

          services.cadvisor = {
            listenAddress = lib.mkDefault "0.0.0.0";
            port = lib.mkDefault 8081;

            extraOptions = [
              "--docker=unix:///var/run/docker.sock"
              "--docker_only=true"
              "--store_container_labels=false"

              "--containerd=/run/docker/containerd/containerd.sock"
              "--containerd-namespace=moby"
            ];
          };

          systemd.services.cadvisor = {
            requires = [ "docker.service" ];
            after = [ "docker.service" ];
          };
        })
      ]
    );
  };
}
