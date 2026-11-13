{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check ports failsEvaluation failedAssertion;
  modules = config.flake.modules.nixos;
  settings = {
    services.tailscale.enable = true;
    deployment.tailscale-dns = {
      dnsInterfaces = [ "tailscale0" ]; metricsInterfaces = [ "metrics0" ];
      upstreams = [ "1.1.1.1" ]; mappings."example.invalid" = "100.64.0.7";
      zone = "internal.example.invalid IN TXT test";
    };
  };
  active = mkSystem [ modules.tailscale-dns ] settings;
  custom = extend active { deployment.tailscale-dns = { dnsPort = 1053; metricsHttpPort = 18080; metricsHttpsPort = 18443; }; };
  disabled = mkSystem [ modules.tailscale-dns ] { services.blocky.enable = false; };
  noTailscale = extend active { services.tailscale.enable = lib.mkForce false; };
  noResolved = extend active { services.resolved.enable = false; };
  optOut = mkSystem [ modules.tailscale-dns ] {
    services.tailscale.enable = true;
    deployment.tailscale-dns = {
      dnsInterfaces = [ "tailscale0" ]; overrideMetricsIntegration = true;
      upstreams = [ "1.1.1.1" ]; mappings = {}; zone = "";
    };
  };
  missing = mkSystem [ modules.tailscale-dns ] { services.tailscale.enable = true; };
  udp = configuration: interface: configuration.config.networking.firewall.interfaces.${interface}.allowedUDPPorts or [];
in
{
  flake.lib.compositionTests.tailscale-dns = {
    explicit-empty-interfaces-is-accepted = check "Explicit empty Blocky interface lists should contribute no DNS or metrics openings."
      ((extend active { deployment.tailscale-dns = { dnsInterfaces = lib.mkForce []; metricsInterfaces = lib.mkForce []; }; }).config.networking.firewall.interfaces == {});
    enables-blocky = check "The DNS feature should enable Blocky." active.config.services.blocky.enable;
    requires-tailscale = check "The DNS feature should assert its Tailscale requirement."
      (failedAssertion noTailscale "The Tailscale DNS feature requires Tailscale.");
    requires-resolved = check "The DNS feature should assert its resolver requirement."
      (failedAssertion noResolved "The Tailscale DNS feature requires systemd-resolved for host DNS resolution.");
    configures-host-resolution = check "DNS integration should free the DNS stub port and stop Tailscale from replacing host DNS."
      (!active.config.services.resolved.settings.Resolve.DNSStubListener
        && builtins.elem "--accept-dns=false" active.config.services.tailscale.extraSetFlags
        && active.config.environment.etc."resolv.conf".source == "/run/systemd/resolve/resolv.conf");
    uses-deployment-dns-values = check "DNS configuration should consume supplied upstreams and custom records."
      (active.config.services.blocky.settings.upstreams.groups.default == [ "1.1.1.1" ]
        && active.config.services.blocky.settings.customDNS.mapping."example.invalid" == "100.64.0.7");
    custom-ports-follow-listeners = check "DNS and metrics listeners should follow their separately configured ports."
      (udp custom "tailscale0" == [ 1053 ] && ports custom "tailscale0" == [ 1053 ]
        && builtins.elem 18080 (ports custom "metrics0") && builtins.elem 18443 (ports custom "metrics0")
        && custom.config.services.blocky.settings.ports.dns == 1053);
    metrics-default-on = check "Blocky Prometheus metrics should be active by default."
      active.config.services.blocky.settings.prometheus.enable;
    metrics-opt-out-removes-support = check "Metrics opt-out should remove its listeners and exposure without requiring metrics interfaces."
      (!(optOut.config.services.blocky.settings ? prometheus)
        && !(optOut.config.services.blocky.settings.ports ? http)
        && !(optOut.config.services.blocky.settings.ports ? https)
        && ports optOut "metrics0" == []);
    missing-upstreams-is-rejected = check "Active Blocky should require upstream DNS servers."
      (failsEvaluation missing.config.services.blocky.settings.upstreams.groups.default);
    missing-mappings-is-rejected = check "Active Blocky should require explicit custom mappings, including an explicit empty set."
      (failsEvaluation missing.config.services.blocky.settings.customDNS.mapping);
    missing-zone-is-rejected = check "Active Blocky should require explicit extra zone records, including an explicit empty string."
      (failsEvaluation missing.config.services.blocky.settings.customDNS.zone);
    missing-dns-interfaces-is-rejected = check "Active Blocky should require explicitly supplied DNS interfaces."
      (failsEvaluation missing.config.networking.firewall.interfaces);
    missing-metrics-interfaces-is-rejected = check "Active Blocky metrics should require explicit interfaces."
      (failsEvaluation (mkSystem [ modules.tailscale-dns ] {
        deployment.tailscale-dns.dnsInterfaces = [ "tailscale0" ];
      }).config.networking.firewall.interfaces);
    disable-removes-support = check "Disabled DNS should need no deployment and remove feature-owned DNS changes."
      (!(disabled.config.systemd.services ? blocky)
        && disabled.config.services.tailscale.extraSetFlags == []
        && disabled.config.networking.firewall.interfaces == {}
        && disabled.config.services.blocky.settings == {});
  };
}
