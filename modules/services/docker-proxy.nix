{
  flake.modules.nixos.docker-proxy =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.deployment.docker-proxy;
    in
    {
      options = {
        virtualisation.oci-containers.containers = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              config = lib.mkIf cfg.enable { networks = lib.mkDefault [ "proxy" ]; };
            }
          );
        };

        deployment.docker-proxy = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Create the proxy network and attach OCI containers to it by default.";
          };
          subnet = lib.mkOption {
            type = lib.types.str;
            description = "IPv4 subnet in CIDR notation for the Docker proxy network.";
          };

          gateway = lib.mkOption {
            type = lib.types.str;
            description = "IPv4 gateway address for the Docker proxy network.";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = config.virtualisation.docker.enable;
            message = "The docker-proxy network requires Docker.";
          }
          {
            assertion = config.virtualisation.oci-containers.backend == "docker";
            message = "The docker-proxy network requires the Docker OCI backend.";
          }
        ];
        systemd.services = lib.mkMerge [
          {
            docker-network-proxy = {
              description = "Create the Docker proxy network";

              wantedBy = [ "multi-user.target" ];
              requires = [ "docker.service" ];
              after = [ "docker.service" ];

              path = [ pkgs.docker ];

              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };

              script = ''
                if  ! docker network inspect proxy >/dev/null 2>&1; then
                  docker network create \
                    --driver bridge \
                    --opt com.docker.network.bridge.name=docker-proxy \
                    --subnet ${lib.escapeShellArg config.deployment.docker-proxy.subnet} \
                    --gateway ${lib.escapeShellArg config.deployment.docker-proxy.gateway} \
                    proxy
                fi
              '';
            };
          }

          (lib.mapAttrs' (
            _: container:
            lib.nameValuePair container.serviceName (
              lib.mkIf (builtins.elem "proxy" container.networks) {
                requires = [ "docker-network-proxy.service" ];
                after = [ "docker-network-proxy.service" ];
              }
            )
          ) config.virtualisation.oci-containers.containers)
        ];
      };
    };
}
