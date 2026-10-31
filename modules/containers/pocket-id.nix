{
  flake.modules.nixos.pocket-id = {
    virtualisation.oci-containers.containers.pocket-id = {
      image = "ghcr.io/pocket-id/pocket-id:v2.19.1";

      autoStart = true;

      networks = [ "proxy" ];

      volumes = [
        "pocket-id-data:/app/data"
      ];

      environmentFiles = [
        "/run/credentials/docker-pocket-id.service/pocket-id.env"
      ];

      environment = {
        APP_URL = "https://id.cimbulka.net";
        TRUSTED_PROXY = "172.18.0.0/16";

        UI_CONFIG_DISABLE = "true";
        ALLOW_USERS_SIGNUPS = "disalbe";
        ALLOW_INSECURE_CALLBACK_URLS = "false";

        ANALYTICS_DISABLED = "true";
        LOG_JSON = "true";
      };

      labels = {
        "traefik.enable" = "true";

        "traefik.http.routers.pocket-id.rule" = "Host(`id.cimbulka.net`)";
        "traefik.http.routers.pocket-id.entrypoints" = "websecure";
        "traefik.http.routers.pocket-id.service" = "pocket-id";
        "traefik.http.routers.pocket-id.tls.certresolver" = "letsencrypt";

        "traefik.http.services.pocket-id.loadbalancer.server.port" = "1411";
      };
    };

    systemd.services.docker-pocket-id = {
      requires = [ "docker-network-proxy.service" ];
      after = [ "docker-network-proxy.service" ];

      serviceConfig.ImportCredential = [
        "pocket-id.env"
      ];
    };
  };
}