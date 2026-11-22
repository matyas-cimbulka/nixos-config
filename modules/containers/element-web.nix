{
  flake.modules.nixos.element-web =
    { config, lib, ... }:
    let
      cfg = config.deployment.element-web;
      containers = config.virtualisation.oci-containers.containers;
      traefikEnabled = containers ? traefik && !cfg.overrideTraefikIntegration;
      homeserver = { "m.homeserver".base_url = "https://${cfg.homeserverDomain}"; };
      jsonFile = name: value: builtins.toFile name (builtins.toJSON value);
      settings = jsonFile "element-web-config.json" {
        default_server_config = homeserver;
        disable_custom_urls = true;
      };
      discovery = jsonFile "matrix-client-discovery.json" homeserver;
    in
    {
      options.deployment.element-web = {
        domain = lib.mkOption {
          type = lib.types.str;
          description = "HTTPS hostname for Element Web.";
        };
        homeserverDomain = lib.mkOption {
          type = lib.types.str;
          description = "HTTPS hostname for the Matrix client API.";
        };
        discoveryDomain = lib.mkOption {
          type = lib.types.str;
          description = "Matrix ID domain on which to serve client discovery through Traefik.";
        };
        overrideTraefikIntegration = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable Element Web and Matrix client discovery routes through the local Traefik container.";
        };
      };

      config = {
        assertions = [
          {
            assertion = config.virtualisation.docker.enable && config.virtualisation.oci-containers.backend == "docker";
            message = "Element Web requires Docker and the Docker OCI backend.";
          }
          {
            assertion = !traefikEnabled || (builtins.elem "proxy" containers.element-web.networks
              && builtins.elem "proxy" containers.traefik.networks);
            message = "Element Web's Traefik integration requires both containers on the proxy network.";
          }
        ];

        virtualisation.oci-containers.containers.element-web = {
          image = "vectorim/element-web:v1.12.35";
          volumes = [ "${settings}:/app/config.json:ro" ]
            ++ lib.optional traefikEnabled "${discovery}:/app/.well-known/matrix/client:ro";

          labels = lib.mkIf traefikEnabled {
            "traefik.enable" = "true";
            "traefik.docker.network" = "proxy";
            "traefik.http.services.element-web.loadbalancer.server.port" = "80";
            "traefik.http.routers.element-web.rule" = "Host(`${cfg.domain}`)";
            "traefik.http.routers.element-web.entrypoints" = "websecure";
            "traefik.http.routers.element-web.service" = "element-web";
            "traefik.http.routers.matrix-client-discovery.rule" = "Host(`${cfg.discoveryDomain}`) && Path(`/.well-known/matrix/client`)";
            "traefik.http.routers.matrix-client-discovery.entrypoints" = "websecure";
            "traefik.http.routers.matrix-client-discovery.service" = "element-web";
            "traefik.http.routers.matrix-client-discovery.middlewares" = "matrix-client-discovery";
            "traefik.http.middlewares.matrix-client-discovery.headers.customresponseheaders.Content-Type" = "application/json";
            "traefik.http.middlewares.matrix-client-discovery.headers.customresponseheaders.Access-Control-Allow-Origin" = "*";
          };
        };
      };
    };
}
