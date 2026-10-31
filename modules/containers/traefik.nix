{
  flake.modules.nixos.traefik = {
    networking.firewall = {
        allowedTCPPorts = [ 80 443 8080 ];
      };

    virtualisation.oci-containers.containers.traefik = {
      image = "traefik:v3.7.17";


      autoStart = true;

      networks = [ "proxy" ];

      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock:ro"
        "traefik-acme:/letsencrypt"
      ];

      environmentFiles = [
        "/run/credentials/docker-traefik.service/cloudflare-dns.env"
      ];

      ports = [
        "80:80"
        "443:443"
        "8080:8080"
      ];

      cmd = [
        "--log.level=INFO"

        "--api=true"
        "--api.insecure=true"
        "--entrypoints.traefik.address=:8080"

        "--providers.docker=true"
        "--providers.docker.exposedbydefault=false"
        "--providers.docker.network=proxy"

        "--entrypoints.web.address=:80"
        "--entrypoints.web.http.redirections.entryPoint.to=websecure"
        "--entrypoints.web.http.redirections.entryPoint.scheme=https"
        "--entrypoints.web.http.redirections.entryPoint.permanent=true"
        "--entrypoints.websecure.address=:443"
        "--entrypoints.websecure.http.tls=true"
        "--entrypoints.websecure.http.tls.certresolver=letsencrypt"

        "--certificatesresolvers.letsencrypt.acme.email=matyas.cimbulka@gmail.com"
        "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
        "--certificatesresolvers.letsencrypt.acme.caserver=https://acme-v02.api.letsencrypt.org/directory"
        "--certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare"
        "--certificatesresolvers.letsencrypt.acme.dnschallenge.resolvers=1.1.1.1:53,1.0.0.1:53"
      ];
    };

    systemd.services.docker-traefik = {
      requires = [ "docker-network-proxy.service" ];
      after = [ "docker-network-proxy.service" ];

      serviceConfig.ImportCredential = [
        "cloudflare-dns.env"
      ];
    };
  };
}