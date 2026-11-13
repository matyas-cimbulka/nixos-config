{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check ports failsEvaluation;
  modules = config.flake.modules.nixos;
  active = mkSystem [ modules.prometheus ] { deployment.prometheus.interfaces = [ "metrics0" ]; };
  disabled = mkSystem [ modules.prometheus ] { services.prometheus.enable = false; };
  missingInterface = mkSystem [ modules.prometheus ] {};
  localAlloy = extend active { services.alloy.enable = true; };
  remote = extend active { deployment.prometheus.systemTargets = [ "remote.example.invalid:12345" ]; };
  mixed = extend remote { services.alloy.enable = true; };
  optOut = extend mixed { deployment.prometheus.overrideAlloyIntegration = true; };
  custom = extend active { services.prometheus = { listenAddress = "::"; port = 19090; }; };
  customAlloy = extend active {
    imports = [ modules.alloy ];
    deployment.alloy = { httpInterfaces = [ "metrics0" ]; httpPort = 12445; overrideLokiIntegration = true; };
  };
  job = configuration: name: lib.findFirst (entry: entry.job_name == name) null configuration.config.services.prometheus.scrapeConfigs;
  targets = configuration: lib.concatMap (entry: entry.targets) (job configuration "system").static_configs;
in
{
  flake.lib.compositionTests.prometheus = {
    enables-service = check "The Prometheus feature should enable Prometheus." active.config.services.prometheus.enable;
    interface-specific-port = check "Prometheus should open its API only on deployment interfaces."
      (ports active "metrics0" == [ 9090 ] && active.config.networking.firewall.allowedTCPPorts == []);
    self-scrape-uses-loopback = check "A wildcard Prometheus listener should scrape itself over loopback."
      (lib.concatMap (entry: entry.targets) (job active "prometheus").static_configs == [ "127.0.0.1:9090" ]);
    ipv6-self-scrape-and-custom-port = check "Prometheus IPv6 self-scrape should use bracketed loopback and the effective port."
      (lib.concatMap (entry: entry.targets) (job custom "prometheus").static_configs == [ "[::1]:19090" ] && ports custom "metrics0" == [ 19090 ]);
    no-alloy-means-no-system-job = check "Prometheus without Alloy or remote targets should have no system scrape job."
      (job active "system" == null);
    native-alloy-enablement-activates-scrape = check "Local Alloy scraping should follow native service enablement."
      (targets localAlloy == [ "127.0.0.1:12345" ]);
    local-and-remote-targets-compose = check "Local Alloy and explicitly wired remote targets should share the system job."
      (targets mixed == [ "127.0.0.1:12345" "remote.example.invalid:12345" ]);
    opt-out-preserves-remote-targets = check "Alloy opt-out should remove the local target and preserve remote targets."
      (targets optOut == [ "remote.example.invalid:12345" ]);
    configured-alloy-port-is-used = check "Local Alloy scraping should follow its configured HTTP port."
      (targets customAlloy == [ "127.0.0.1:12445" ]);
    missing-interface-is-rejected = check "Active Prometheus should require explicitly supplied interfaces."
      (failsEvaluation missingInterface.config.networking.firewall.interfaces);
    disable-removes-support = check "Disabled Prometheus should need no deployment values and remove its scrape jobs and firewall contribution."
      (!(disabled.config.systemd.services ? prometheus)
        && disabled.config.services.prometheus.scrapeConfigs == []
        && disabled.config.networking.firewall.interfaces == {});
  };
}
