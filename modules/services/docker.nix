{ config, ... }:
{
  flake.modules.nixos.docker = { pkgs, ... }: {
    virtualisation = {
      docker.enable = true;

      oci-containers.backend = "docker";
    };

    systemd.services = {
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
              --subnet 172.18.0.0/16 \
              --gateway 172.18.0.1 \
              proxy
          fi
        '';
      };
    };
  };
}