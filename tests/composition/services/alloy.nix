{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check ports failsEvaluation failedAssertion cadvisorInactive alloyTexts;
  modules = config.flake.modules.nixos;
  alloySettings.deployment.alloy = {
    httpInterfaces = [ "test0" ];
    lokiEndpoint = "http://loki.example.invalid/loki/api/v1/push";
  };
  alloyOnly = mkSystem [ modules.alloy ] alloySettings;
  dockerAlloy = extend alloyOnly {
    imports = [ modules.docker ];
    deployment.cadvisor.metricsInterface = "test0";
  };
  dockerAlloyOptOut = extend dockerAlloy {
    deployment.cadvisor.overrideIntegration = true;
  };
  alloyWithNativeDocker = extend alloyOnly {
    virtualisation.docker.enable = true;
    deployment.cadvisor.metricsInterface = "test0";
  };
  dockerAlloyReversed = mkSystem [ modules.docker modules.alloy ] {
    deployment = alloySettings.deployment // {
      cadvisor.metricsInterface = "test0";
    };
  };
  dockerAlloyDockerDisabled = extend dockerAlloy { virtualisation.docker.enable = false; };
  dockerAlloyAlloyDisabled = extend dockerAlloy { services.alloy.enable = false; };
  missingCadvisorInterface = extend alloyOnly { imports = [ modules.docker ]; };
  optOutWithoutInterface = extend missingCadvisorInterface {
    deployment.cadvisor.overrideIntegration = true;
  };
  disabledWithoutInterface = extend missingCadvisorInterface {
    services.cadvisor.enable = false;
  };
  missingAlloyInterface = mkSystem [ modules.alloy ] {
    deployment.alloy.lokiEndpoint = "http://loki.example.invalid/loki/api/v1/push";
  };
  missingLokiEndpoint = mkSystem [ modules.alloy ] {
    deployment.alloy.httpInterfaces = [ "test0" ];
  };
  lokiOptOut = extend missingLokiEndpoint { deployment.alloy.overrideLokiIntegration = true; };
  alloyDisabled = mkSystem [ modules.alloy ] { services.alloy.enable = false; };
  alloyCustom = extend alloyOnly {
    deployment.alloy = { httpInterfaces = lib.mkForce [ "metrics0" "tailscale0" ]; httpPort = 12445; };
  };
  traceSettings = {
    deployment = {
      alloy = { httpInterfaces = [ "metrics0" ]; overrideLokiIntegration = true; tempoEndpoint = "tempo.example.invalid:4317"; };
      cadvisor.metricsInterface = "metrics0";
      docker-proxy = { subnet = "172.30.0.0/24"; gateway = "172.30.0.1"; };
    };
    # Receiver activation must follow final OCI declarations, even without sender modules.
    virtualisation.oci-containers.containers.pocket-id.image = "example.invalid/pocket-id:test";
  };
  receiver = mkSystem [ modules.docker modules.docker-proxy modules.alloy ] traceSettings;
  bothSenders = extend receiver {
    virtualisation.oci-containers.containers.traefik.image = "example.invalid/traefik:test";
  };
  noProxy = extend receiver { deployment.docker-proxy.enable = false; };
  missingTempo = mkSystem [ modules.docker modules.docker-proxy modules.alloy ] (traceSettings // {
    deployment = traceSettings.deployment // {
      alloy = builtins.removeAttrs traceSettings.deployment.alloy [ "tempoEndpoint" ];
    };
  });
in
{
  flake.lib.compositionTests.alloy = {
    trace-receiver-follows-final-container-config = check "Alloy should create its shared receiver for a native OCI sender declaration."
      (lib.hasInfix "172.30.0.1:4318" receiver.config.environment.etc."alloy/traces.alloy".text
        && lib.hasInfix "tempo.example.invalid:4317" receiver.config.environment.etc."alloy/traces.alloy".text
        && ports receiver "docker-proxy" == [ 4318 ]);
    two-senders-share-one-receiver = check "Multiple tracing senders should share one Alloy receiver."
      (bothSenders.config.environment.etc."alloy/traces.alloy".text == receiver.config.environment.etc."alloy/traces.alloy".text
        && ports bothSenders "docker-proxy" == [ 4318 ]);
    trace-receiver-orders-after-network = check "Alloy's trace receiver should wait for its proxy network."
      (builtins.elem "docker-network-proxy.service" receiver.config.systemd.services.alloy.requires
        && builtins.elem "docker-network-proxy.service" receiver.config.systemd.services.alloy.after);
    trace-receiver-requires-network-capability = check "Alloy should assert the proxy-network requirement for an active trace receiver."
      (failedAssertion noProxy "Alloy's Docker trace receiver requires the docker-proxy network feature.");
    active-tracing-requires-tempo-endpoint = check "An active Alloy trace pipeline should require its deployment Tempo endpoint."
      (failsEvaluation missingTempo.config.environment.etc."alloy/traces.alloy".text);
    docker-alloy-enables-cadvisor =
      assert lib.assertMsg dockerAlloy.config.services.cadvisor.enable
        "Docker + Alloy should automatically enable cAdvisor.";
      true;

    docker-alloy-respects-cadvisor-opt-out =
      assert lib.assertMsg (!dockerAlloyOptOut.config.services.cadvisor.enable)
        "Opting out should disable automatic cAdvisor activation.";
      true;

    cadvisor-opt-out-removes-metrics-port =
      assert lib.assertMsg (!(builtins.elem 8081 dockerAlloyOptOut.config.networking.firewall.interfaces.test0.allowedTCPPorts))
        "Opting out of cAdvisor should remove its metrics port from test0 interface.";
      true;

    alloy-without-docker-disables-cadvisor =
      assert lib.assertMsg (!alloyOnly.config.services.cadvisor.enable)
        "Alloy without Docker should leave cAdvisor disabled.";
      true;

    native-docker-activates-cadvisor =
      assert lib.assertMsg alloyWithNativeDocker.config.services.cadvisor.enable
        "Docker enabled through its native option should activate cAdvisor with Alloy.";
      true;

    import-order-preserves-integration = check "Reversing imports should preserve cAdvisor integration."
      (dockerAlloyReversed.config.services.cadvisor.enable
        && ports dockerAlloyReversed "test0" == ports dockerAlloy "test0"
        && dockerAlloyReversed.config.systemd.services.cadvisor.requires
          == dockerAlloy.config.systemd.services.cadvisor.requires);

    cadvisor-opt-out-removes-support = check "Opt-out should remove cAdvisor's unit, flags, and firewall opening."
      (cadvisorInactive dockerAlloyOptOut);

    docker-disable-removes-cadvisor-support = check "Disabling Docker should deactivate automatic cAdvisor integration."
      (cadvisorInactive dockerAlloyDockerDisabled);

    alloy-disable-removes-cadvisor-support = check "Disabling Alloy should deactivate automatic cAdvisor integration."
      (cadvisorInactive dockerAlloyAlloyDisabled);

    alloy-only-has-no-cadvisor-support = check "Alloy alone should leave no cAdvisor supporting configuration."
      (cadvisorInactive alloyOnly);

    opted-out-cadvisor-needs-no-interface = check "Opted-out integration should not require a metrics interface."
      (cadvisorInactive optOutWithoutInterface);

    explicitly-disabled-cadvisor-needs-no-interface = check "Explicitly disabled cAdvisor should not require a metrics interface."
      (cadvisorInactive disabledWithoutInterface);

    alloy-enables-service-and-exporter = check "Alloy should enable its service and Unix exporter."
      (alloyOnly.config.services.alloy.enable
        && lib.hasInfix "prometheus.exporter.unix" alloyOnly.config.environment.etc."alloy/config.alloy".text);

    alloy-opens-http-port = check "Alloy should open its default HTTP port on the selected interface."
      (builtins.elem 12345 (ports alloyOnly "test0")
        && builtins.elem "--server.http.listen-addr=0.0.0.0:12345" alloyOnly.config.services.alloy.extraFlags
        && !(builtins.elem 12345 alloyOnly.config.networking.firewall.allowedTCPPorts));

    alloy-http-settings-are-overridable = check "Alloy's listener and firewall should follow its configured port and interfaces."
      (builtins.elem "--server.http.listen-addr=0.0.0.0:12445" alloyCustom.config.services.alloy.extraFlags
        && builtins.elem 12445 (ports alloyCustom "metrics0")
        && builtins.elem 12445 (ports alloyCustom "tailscale0")
        && !(builtins.elem 12345 (ports alloyCustom "metrics0"))
        && !(builtins.elem 12445 (ports alloyCustom "test0")));

    active-alloy-requires-http-interfaces = check "Active Alloy should reject missing HTTP interfaces."
      (failsEvaluation missingAlloyInterface.config.networking.firewall.interfaces);

    alloy-forwards-logs-by-default = check "Alloy should forward journal logs to the supplied Loki endpoint."
      (lib.hasInfix "loki.source.journal" alloyOnly.config.environment.etc."alloy/logs.alloy".text
        && lib.hasInfix "http://loki.example.invalid/loki/api/v1/push"
          alloyOnly.config.environment.etc."alloy/logs.alloy".text);

    active-loki-integration-requires-endpoint = check "Active log forwarding should require a Loki endpoint."
      (failsEvaluation missingLokiEndpoint.config.environment.etc."alloy/logs.alloy".text);

    loki-opt-out-removes-logs-without-endpoint = check "Loki opt-out should remove log forwarding without requiring its endpoint."
      (lokiOptOut.config.services.alloy.enable
        && lokiOptOut.config.environment.etc ? "alloy/config.alloy"
        && !(lokiOptOut.config.environment.etc ? "alloy/logs.alloy")
        && builtins.deepSeq (alloyTexts lokiOptOut) true);

    alloy-without-trace-senders-needs-no-tempo = check "Alloy with no trace senders should not create a receiver or need Tempo."
      (!(dockerAlloy.config.environment.etc ? "alloy/traces.alloy")
        && !(builtins.elem 4318 (ports dockerAlloy "docker-proxy"))
        && !(builtins.elem "docker-network-proxy.service" dockerAlloy.config.systemd.services.alloy.requires)
        && builtins.deepSeq (alloyTexts dockerAlloy) true);

    disabled-alloy-needs-no-deployment-and-removes-support = check "Disabled Alloy should remove generated config, units, flags, and firewall contributions."
      (!alloyDisabled.config.services.alloy.enable
        && cadvisorInactive alloyDisabled
        && !(alloyDisabled.config.systemd.services ? alloy)
        && alloyDisabled.config.services.alloy.extraFlags == []
        && !(alloyDisabled.config.environment.etc ? "alloy/config.alloy")
        && !(alloyDisabled.config.environment.etc ? "alloy/logs.alloy")
        && !(alloyDisabled.config.environment.etc ? "alloy/traces.alloy")
        && builtins.deepSeq alloyDisabled.config.networking.firewall.interfaces true
        && builtins.deepSeq (alloyTexts alloyDisabled) true);
  };
}
