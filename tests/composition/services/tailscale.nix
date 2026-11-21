{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check ports failsEvaluation failedAssertion;
  modules = config.flake.modules.nixos;
  settings = {
    services.tailscale.authKeyFile = "/run/test-secrets/tailscale";
    deployment.tailscale = { interfaces = [ "transport0" ]; metricsInterfaces = [ "metrics0" ]; };
  };
  active = mkSystem [ modules.tailscale ] settings;
  custom = extend active { services.tailscale.port = 14164; deployment.tailscale.metricsPort = 19250; };
  server = mkSystem [ modules.tailscale-server ] settings;
  guest = mkSystem [ modules.tailscale-microvm ] settings;
  disabled = mkSystem [ modules.tailscale-microvm ] { services.tailscale.enable = false; };
  noKey = extend active { services.tailscale.authKeyFile = lib.mkForce null; };
  interactive = mkSystem [ modules.tailscale ] {
    deployment.tailscale = { enrollment = "interactive"; interfaces = []; overrideMetricsIntegration = true; };
  };
  interactiveWithKey = extend interactive { services.tailscale.authKeyFile = "/run/test-secrets/unwanted-key"; };
  globalFirewall = extend active { services.tailscale.openFirewall = true; };
  noNft = extend active { networking.nftables.enable = false; };
  noMetricsInterfaces = extend active { deployment.tailscale.metricsInterfaces = lib.mkForce []; };
  noTransportInterfaces = mkSystem [ modules.tailscale ] {
    services.tailscale.authKeyFile = "/run/test-secrets/tailscale";
    deployment.tailscale.overrideMetricsIntegration = true;
  };
  optOut = mkSystem [ modules.tailscale ] {
    services.tailscale.authKeyFile = "/run/test-secrets/tailscale";
    deployment.tailscale = { interfaces = [ "transport0" ]; overrideMetricsIntegration = true; };
  };
  udp = configuration: interface: configuration.config.networking.firewall.interfaces.${interface}.allowedUDPPorts or [];
in
{
  flake.lib.compositionTests.tailscale = {
    personal-enrollment-needs-no-key = check "Interactive Tailscale enrollment should run the client without an auth key, tags, metrics, or automatic login."
      (interactive.config.services.tailscale.enable && interactive.config.services.tailscale.authKeyFile == null
        && !(interactive.config.systemd.services ? tailscaled-autoconnect)
        && !(interactive.config.systemd.services ? tailscale-metrics)
        && interactive.config.services.tailscale.extraUpFlags == []
        && !(failedAssertion interactive "The Tailscale feature requires services.tailscale.authKeyFile supplied by the deployment."));
    personal-enrollment-rejects-server-key = check "Interactive enrollment should reject accidental automatic enrollment credentials."
      (failedAssertion interactiveWithKey "Interactive Tailscale enrollment requires services.tailscale.authKeyFile = null.");
    explicit-empty-transport-interfaces-is-accepted = check "Explicit empty Tailscale transport interfaces should preserve metrics without UDP openings."
      (let empty = extend active { deployment.tailscale.interfaces = lib.mkForce []; };
       in udp empty "transport0" == [] && ports empty "metrics0" == [ 9250 ]);
    enables-service = check "The Tailscale feature should enable tailscaled." active.config.services.tailscale.enable;
    separates-transport-and-metrics = check "Tailscale UDP transport and TCP metrics should use their selected interfaces."
      (udp active "transport0" == [ active.config.services.tailscale.port ]
        && ports active "metrics0" == [ 9250 ] && ports active "transport0" == []
        && active.config.networking.firewall.allowedUDPPorts == []);
    custom-ports-update-rules-and-listener = check "Tailscale custom ports should update firewall, NFT, and the listener."
      (udp custom "transport0" == [ 14164 ] && ports custom "metrics0" == [ 19250 ]
        && lib.hasInfix "0.0.0.0:19250" custom.config.systemd.services.tailscale-metrics.serviceConfig.ExecStart
        && lib.hasInfix "19250" custom.config.networking.nftables.tables.tailscale-metrics.content);
    metrics-restricts-incoming-interface = check "Tailscale metrics should reject other incoming interfaces before destination NAT."
      (lib.hasInfix "priority -110" active.config.networking.nftables.tables.tailscale-metrics.content
        && lib.hasInfix ''iifname != { "metrics0" }'' active.config.networking.nftables.tables.tailscale-metrics.content
        && lib.hasInfix "counter drop" active.config.networking.nftables.tables.tailscale-metrics.content);
    missing-key-declares-failure = check "Tailscale should require a deployment-owned authentication file."
      (failedAssertion noKey "The Tailscale feature requires services.tailscale.authKeyFile supplied by the deployment.");
    rejects-global-firewall-opening = check "Tailscale should reject an unrestricted native firewall opening."
      (failedAssertion globalFirewall "The Tailscale feature opens its transport port per deployment interface; keep services.tailscale.openFirewall = false.");
    metrics-requires-nftables = check "Tailscale metrics should assert its NFT requirement."
      (failedAssertion noNft "Tailscale metrics interface restrictions require networking.nftables.enable.");
    metrics-requires-nonempty-interfaces = check "Active Tailscale metrics should reject empty interface selection."
      (failedAssertion noMetricsInterfaces "Tailscale metrics require a non-empty deployment.tailscale.metricsInterfaces list, or set overrideMetricsIntegration = true.");
    missing-transport-interfaces-is-rejected = check "Active Tailscale should require explicit transport interfaces."
      (failsEvaluation noTransportInterfaces.config.networking.firewall.interfaces);
    metrics-opt-out-removes-support = check "Metrics opt-out should remove its listener, firewall, and NFT table without needing metrics interfaces."
      (!(optOut.config.systemd.services ? tailscale-metrics)
        && !(optOut.config.networking.nftables.tables ? tailscale-metrics)
        && udp optOut "transport0" != [] && ports optOut "transport0" == []);
    server-wrapper-tags-server = check "The server wrapper should advertise its server tag."
      (builtins.elem "--advertise-tags=tag:server" server.config.services.tailscale.extraUpFlags);
    guest-wrapper-waits-for-dns = check "The guest wrapper should advertise its VM tag and wait for DNS before enrollment."
      (builtins.elem "--advertise-tags=tag:vm" guest.config.services.tailscale.extraUpFlags
        && builtins.elem "systemd-networkd-wait-online.service" guest.config.systemd.services.tailscaled-autoconnect.requires
        && builtins.elem "--dns" guest.config.systemd.network.wait-online.extraArgs);
    disable-removes-support = check "Disabled Tailscale should need no deployment and remove metrics and enrollment support."
      (!(disabled.config.systemd.services ? tailscale-metrics)
        && !(disabled.config.systemd.services ? tailscaled-autoconnect)
        && !(disabled.config.networking.nftables.tables ? tailscale-metrics)
        && disabled.config.networking.firewall.interfaces == {}
        && disabled.config.services.tailscale.extraUpFlags == []);
  };
}
