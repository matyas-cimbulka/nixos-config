{ deploymentHelpers, lib, ... }:
let
  inherit (deploymentHelpers) host guest check credentialWiring tcpPorts udpPorts internalHost internalDomain;
  anderson = guest "anderson";
  behemoth = guest "behemoth";
  dns = anderson.deployment.tailscale-dns;
  lan = anderson.deployment.microvm.interfaceName;
in
{
  flake.lib.deploymentTests.anderson = {
    tailscale-credential-wiring = credentialWiring {
      vm = "anderson"; service = "tailscaled-autoconnect"; name = "tailscale-vm-oauth";
      source = host.sops.secrets.tailscale-vm-oauth.path;
      consumedPaths = [ anderson.services.tailscale.authKeyFile ];
    };
    dns-is-exposed-only-to-tailnet = check "Anderson DNS must be selected on Tailscale, with TCP/UDP DNS closed on the guest LAN."
      (dns.dnsInterfaces == [ "tailscale0" ]
        && builtins.elem dns.dnsPort (tcpPorts anderson "tailscale0")
        && builtins.elem dns.dnsPort (udpPorts anderson "tailscale0")
        && !(builtins.elem dns.dnsPort (tcpPorts anderson lan))
        && !(builtins.elem dns.dnsPort (udpPorts anderson lan))
        && !(builtins.elem dns.dnsPort anderson.networking.firewall.allowedTCPPorts)
        && !(builtins.elem dns.dnsPort anderson.networking.firewall.allowedUDPPorts));
    blocky-metrics-are-internal = check "Anderson Blocky metrics must stay on the internal guest interface."
      (dns.metricsInterfaces == [ lan ] && anderson.services.blocky.settings.prometheus.enable
        && lib.all (port: builtins.elem port (tcpPorts anderson lan)
          && !(builtins.elem port (tcpPorts anderson "tailscale0"))) [ dns.metricsHttpPort dns.metricsHttpsPort ]);
    public-zone-uses-ingress-tailnet-address = check "Public service DNS must retain the explicitly assigned Behemoth tailnet address, not an internal bridge address."
      (dns.mappings."cimbulka.net" == "100.119.128.83");
    internal-zone-is-excluded-from-public-wildcard = check "The internal zone must remain distinct from the public wildcard mapping."
      (anderson.services.blocky.settings.customDNS.filterUnmappedTypes
        && lib.hasInfix "${internalDomain}." dns.zone
        && lib.hasInfix "TXT" dns.zone);
    host-public-dns-aliases-follow-ingress = check "Tycho's internal DNS aliases must route ID and Grafana hostnames to Behemoth."
      (builtins.elem "${behemoth.deployment.pocket-id.domain},${internalHost behemoth}" host.services.dnsmasq.settings.cname
        && builtins.elem "${(guest "thoth").deployment.grafana.domain},${internalHost behemoth}" host.services.dnsmasq.settings.cname);
    guest-resolver-keeps-host-dns = check "Anderson must retain host DNS resolution without Tailscale overwriting it or the stub occupying port 53."
      (!anderson.services.resolved.settings.Resolve.DNSStubListener
        && builtins.elem "--accept-dns=false" anderson.services.tailscale.extraSetFlags
        && anderson.environment.etc."resolv.conf".source == "/run/systemd/resolve/resolv.conf");
  };
}
