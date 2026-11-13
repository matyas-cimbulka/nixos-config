{
  flake.modules.nixos.traefik =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      yamlFormat = pkgs.formats.yaml { };

      dynamicConfig = yamlFormat.generate "traefik-dynamic.yaml" config.deployment.traefik.dynamicConfig;

      alloyIntegrationEnabled =
        config.services.alloy.enable && !config.deployment.traefik.overrideAlloyIntegration;

      exposedPorts = lib.unique (
        lib.concatLists (builtins.attrValues config.deployment.traefik.portsByInterface)
      );

      exposureRules =
        lib.concatMapStringsSep "\n"
          (
            port:
            let
              interfaces = builtins.attrNames (
                lib.filterAttrs (_: ports: builtins.elem port ports) config.deployment.traefik.portsByInterface
              );
              interfaceMatch = lib.optionalString (interfaces != [ ]) (
                "iifname != { " + lib.concatMapStringsSep ", " builtins.toJSON interfaces + " } "
              );
            in
            "fib daddr type local ct direction original tcp dport ${toString port} ${interfaceMatch}counter drop"
          )
          [ 80 443 8080 ];
    in
    {
      options.deployment.traefik = {
        portsByInterface = lib.mkOption {
          default = throw "Set deployment.traefik.portsByInterface explicitly; use {} to publish no ports.";
          type = lib.types.attrsOf (
            lib.types.listOf (
              lib.types.enum [ 80 443 8080 ]
            )
          );
          description = "Traefik TCP ports permitted on each incoming interface. Port 8080 serves administration and metrics.";
        };

        dnsServer = lib.mkOption {
          type = lib.types.str;
          description = "DNS server used by the Traefik container.";
        };

        acmeEmail = lib.mkOption {
          type = lib.types.str;
          description = "Contact email for ACME certificate registration.";
        };

        environmentFile = lib.mkOption {
          type = lib.types.strMatching "/.*";
          description = "Absolute runtime path to the environment file containing DNS-provider credentials. The deployment supplies the file and startup ordering.";
        };

        dynamicConfig = lib.mkOption {
          type = lib.types.attrsOf yamlFormat.type;
          default = { };
          description = "Traefik dynamic configuration";
        };

        overrideAlloyIntegration = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable Traefik tracing integration with Alloy.";
        };
      };

      config = {
        assertions = [
          {
            assertion = config.virtualisation.docker.enable;
            message = "The Traefik container requires Docker.";
          }
          {
            assertion = config.virtualisation.oci-containers.backend == "docker";
            message = "The Traefik container requires `docker` backend.";
          }
          {
            assertion = config.systemd.services.docker-network-proxy.enable or false;
            message = "The Traefik container requires the `docker-proxy` network feature.";
          }
          {
            assertion = config.networking.nftables.enable;
            message = "Traefik interface restrictions require networking.nftables.enable.";
          }
        ];

        networking = {
          firewall.interfaces = lib.mapAttrs (_: ports: {
            allowedTCPPorts = ports;
          }) config.deployment.traefik.portsByInterface;

          nftables = {
            enable = lib.mkDefault true;
            tables.traefik-exposure = {
              family = "inet";
              content = ''
                chain published_ports {
                  type filter hook prerouting priority -110; policy accept;
                  # Filter host ports before Docker's destination NAT at priority -100.
                  ${exposureRules}
                }
              '';
            };
          };
        };

        virtualisation.oci-containers.containers.traefik = {
          image = "traefik:v3.7.17";

          autoStart = true;

          extraOptions = [ "--dns=${config.deployment.traefik.dnsServer}" ];

          volumes = [
            "/var/run/docker.sock:/var/run/docker.sock:ro"
            "traefik-acme:/letsencrypt"
            "${dynamicConfig}:/etc/traefik/dynamic.yaml:ro"
          ];

          environmentFiles = [ config.deployment.traefik.environmentFile ];

          ports = map (port: "${toString port}:${toString port}") exposedPorts;

          cmd = [
            "--log.level=INFO"

            "--api=true"
            "--api.insecure=true"
            "--entrypoints.traefik.address=:8080"

            "--providers.docker=true"
            "--providers.docker.exposedbydefault=false"
            "--providers.docker.network=proxy"

            "--providers.file.filename=/etc/traefik/dynamic.yaml"
            "--providers.file.watch=false"

            "--entrypoints.web.address=:80"
            "--entrypoints.web.http.redirections.entryPoint.to=websecure"
            "--entrypoints.web.http.redirections.entryPoint.scheme=https"
            "--entrypoints.web.http.redirections.entryPoint.permanent=true"
            "--entrypoints.websecure.address=:443"
            "--entrypoints.websecure.http.tls=true"
            "--entrypoints.websecure.http.tls.certresolver=letsencrypt"

            "--certificatesresolvers.letsencrypt.acme.email=${config.deployment.traefik.acmeEmail}"
            "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
            "--certificatesresolvers.letsencrypt.acme.caserver=https://acme-v02.api.letsencrypt.org/directory"
            "--certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare"
            "--certificatesresolvers.letsencrypt.acme.dnschallenge.resolvers=1.1.1.1:53,1.0.0.1:53"

            "--metrics.prometheus=true"
            "--metrics.prometheus.entrypoint=traefik"
            "--metrics.prometheus.addrouterslabels=true"

            "--accesslog=true"
            "--accesslog.format=json"
          ]
          ++ lib.optionals alloyIntegrationEnabled [
            "--tracing.otlp.http=true"
            "--tracing.otlp.http.endpoint=http://${config.deployment.docker-proxy.gateway}:4318/v1/traces"
          ];
        };

        systemd.services.docker-traefik = {
          requires = [ "nftables.service" ];
          after = [ "nftables.service" ];
        };
      };
    };
}
