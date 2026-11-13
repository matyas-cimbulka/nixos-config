{ deploymentHelpers, lib, ... }:
let
  inherit (deploymentHelpers) host guest check credentialWiring sameMembers tcpPorts internalHost commandValue;
  behemoth = guest "behemoth";
  thoth = guest "thoth";
  containers = behemoth.virtualisation.oci-containers.containers;
  lan = behemoth.deployment.microvm.interfaceName;
  proxy = behemoth.deployment.docker-proxy;
  traceEndpoint = "http://${proxy.gateway}:4318/v1/traces";
  grafana = behemoth.deployment.traefik.dynamicConfig.http;
in
{
  flake.lib.deploymentTests.behemoth = {
    traefik-credential-wiring = credentialWiring {
      vm = "behemoth"; service = containers.traefik.serviceName; name = "cloudflare-dns.env";
      source = host.sops.templates."cloudflare-dns.env".path;
      consumedPaths = containers.traefik.environmentFiles;
    };
    pocket-id-credential-wiring = credentialWiring {
      vm = "behemoth"; service = containers.pocket-id.serviceName; name = "pocket-id.env";
      source = host.sops.templates."pocket-id.env".path;
      consumedPaths = containers.pocket-id.environmentFiles;
    };
    tailscale-credential-wiring = credentialWiring {
      vm = "behemoth"; service = "tailscaled-autoconnect"; name = "tailscale-vm-oauth";
      source = host.sops.secrets.tailscale-vm-oauth.path;
      consumedPaths = [ behemoth.services.tailscale.authKeyFile ];
    };
    environment-templates-use-intended-secrets = check "Behemoth environment templates must reference their intended SOPS secrets."
      (lib.hasInfix "CF_DNS_API_TOKEN=${host.sops.placeholder.cloudflare-dns-api-token}" host.sops.templates."cloudflare-dns.env".content
        && lib.hasInfix "ENCRYPTION_KEY=${host.sops.placeholder.pocket-id-encryption-key}" host.sops.templates."pocket-id.env".content
        && lib.hasInfix "SMTP_PASSWORD=${host.sops.placeholder.pocket-id-smtp-password}" host.sops.templates."pocket-id.env".content
        && host.sops.templates."cloudflare-dns.env".mode == "0400"
        && host.sops.templates."pocket-id.env".mode == "0400");
    traefik-exposure-is-explicit = check "Behemoth must explicitly permit 80/443/8080 on LAN and Tailscale for the current debugging policy."
      (sameMembers (builtins.attrNames behemoth.deployment.traefik.portsByInterface) [ lan "tailscale0" ]
        && sameMembers behemoth.deployment.traefik.portsByInterface.${lan} [ 80 443 8080 ]
        && sameMembers behemoth.deployment.traefik.portsByInterface.tailscale0 [ 80 443 8080 ]
        && lib.all (port: builtins.elem port (tcpPorts behemoth lan) && builtins.elem port (tcpPorts behemoth "tailscale0")) [ 80 443 8080 ]);
    traefik-publication-matches-exposure = check "Traefik must publish exactly the deployment-approved host ports."
      (sameMembers containers.traefik.ports [ "80:80" "443:443" "8080:8080" ]
        && behemoth.networking.nftables.tables ? traefik-exposure
        && lib.hasInfix "priority -110" behemoth.networking.nftables.tables.traefik-exposure.content);
    pocket-id-routing-uses-proxy-network = check "Pocket ID and Traefik must share the proxy network and publish the intended ID route."
      (builtins.elem "proxy" containers.pocket-id.networks && builtins.elem "proxy" containers.traefik.networks
        && containers.pocket-id.labels."traefik.http.routers.pocket-id.rule" == "Host(`${behemoth.deployment.pocket-id.domain}`)"
        && containers.pocket-id.labels."traefik.http.services.pocket-id.loadbalancer.server.port" == "1411"
        && containers.pocket-id.labels."traefik.docker.network" == "proxy"
        && commandValue "--providers.docker.network=" containers.traefik.cmd == "proxy"
        && containers.pocket-id.environment.TRUST_PROXY == proxy.subnet);
    pocket-id-app-is-not-published-on-host = check "Co-located Pocket ID must publish only its separate metrics endpoint."
      (containers.pocket-id.ports == [ "${toString behemoth.deployment.pocket-id.metricsPort}:${toString behemoth.deployment.pocket-id.metricsPort}" ]);
    metrics-and-traces-remain-enabled = check "Behemoth must retain Pocket ID metrics and both application trace senders."
      (containers.pocket-id.environment.OTEL_METRICS_EXPORTER == "prometheus"
        && containers.pocket-id.environment.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT == traceEndpoint
        && commandValue "--tracing.otlp.http.endpoint=" containers.traefik.cmd == traceEndpoint
        && lib.hasInfix "${proxy.gateway}:4318" behemoth.environment.etc."alloy/traces.alloy".text);
    grafana-route-follows-thoth = check "The ingress Grafana route must use Thoth's actual hostname, HTTP port, and public domain."
      (grafana.routers.grafana.rule == "Host(`${thoth.deployment.grafana.domain}`)"
        && grafana.routers.grafana.service == "grafana"
        && grafana.services.grafana.loadBalancer.servers == [ {
          url = "http://${internalHost thoth}:${toString thoth.services.grafana.settings.server.http_port}";
        } ]);
    dns-server-follows-host-bridge = check "Traefik container DNS must use Tycho's bridge DNS service."
      (behemoth.deployment.traefik.dnsServer == deploymentHelpers.bridgeAddress
        && builtins.elem "--dns=${deploymentHelpers.bridgeAddress}" containers.traefik.extraOptions);
  };
}
