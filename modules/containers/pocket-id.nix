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
        TRUST_PROXY = "172.18.0.0/16";

        UI_CONFIG_DISABLED = "true";
        ALLOW_USERS_SIGNUPS = "disabled";
        ALLOW_INSECURE_CALLBACK_URLS = "false";

        SMTP_HOST = "smtp.purelymail.com";
        SMTP_PORT = "587";
        SMTP_FROM = "id@cimbulka.net";
        SMTP_USER = "id@cimbulka.net";

        SMTP_TLS = "starttls";
        EMAIL_LOGIN_NOTIFICATION_ENABLED = "true";
        EMAIL_ONE_TIME_ACCESS_AS_ADMIN_ENABLED = "true";
        EMAIL_VERIFICATION_ENABLED = "true";

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