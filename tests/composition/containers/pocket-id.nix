{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check ports failsEvaluation failedAssertion;
  modules = config.flake.modules.nixos;
  settings.deployment.pocket-id = {
    domain = "id.example.invalid"; trustedProxies = [ "172.30.0.0/24" ];
    dataVolume = "test-pocket-data"; environmentFile = "/run/test-secrets/pocket.env";
    metricsInterfaces = [ "metrics0" ];
    smtp = { host = "smtp.example.invalid"; port = 587; from = "id@example.invalid"; user = "test"; tls = "starttls"; };
  };
  active = mkSystem [ modules.docker modules.pocket-id ] settings;
  custom = extend active { deployment.pocket-id.metricsPort = 19464; };
  metricsOptOut = mkSystem [ modules.docker modules.pocket-id ] (settings // {
    deployment.pocket-id = (builtins.removeAttrs settings.deployment.pocket-id [ "metricsInterfaces" ]) // { overrideMetricsIntegration = true; };
  });
  # Native OCI containers normally enable Docker themselves; force an invalid fixture.
  noDocker = extend active { virtualisation.docker.enable = lib.mkForce false; };
  podman = extend active { virtualisation.oci-containers.backend = "podman"; };
  noNft = extend active { networking.nftables.enable = false; };
  noMetricsInterfaces = extend active { deployment.pocket-id.metricsInterfaces = lib.mkForce []; };
  missing = name: mkSystem [ modules.docker modules.pocket-id ] (settings // {
    deployment.pocket-id = builtins.removeAttrs settings.deployment.pocket-id [ name ];
  });
  noTrustedProxy = extend active { deployment.pocket-id.trustedProxies = lib.mkForce []; };
  ingress = extend active {
    imports = [ modules.docker-proxy ];
    deployment.docker-proxy = { subnet = "172.30.0.0/24"; gateway = "172.30.0.1"; };
    # Native OCI declaration verifies composition follows actual container presence.
    virtualisation.oci-containers.containers.traefik.image = "example.invalid/traefik:test";
  };
  ingressOptOut = extend ingress { deployment.pocket-id.overrideTraefikIntegration = true; };
  wrongNetwork = extend ingress { virtualisation.oci-containers.containers.pocket-id.networks = [ "private" ]; };
  tracing = extend ingress {
    imports = [ modules.alloy ];
    deployment = {
      cadvisor.metricsInterface = "metrics0";
      alloy = { httpInterfaces = [ "metrics0" ]; overrideLokiIntegration = true; tempoEndpoint = "tempo.example.invalid:4317"; };
    };
  };
  traceOptOut = extend tracing { deployment.pocket-id.overrideAlloyIntegration = true; };
  tracingWithoutNetwork = extend tracing { virtualisation.oci-containers.containers.pocket-id.networks = [ "private" ]; };
  container = configuration: configuration.config.virtualisation.oci-containers.containers.pocket-id;
in
{
  flake.lib.compositionTests.pocket-id = {
    uses-deployment-values-and-secret-reference = check "Pocket ID should consume deployment URL, storage, SMTP, and runtime credentials."
      ((container active).environment.APP_URL == "https://id.example.invalid"
        && (container active).environment.SMTP_PORT == "587"
        && (container active).environmentFiles == [ "/run/test-secrets/pocket.env" ]
        && (container active).volumes == [ "test-pocket-data:/app/data" ]);
    empty-trusted-proxies-disables-trust = check "An explicit empty trusted-proxy list should disable proxy trust."
      ((container noTrustedProxy).environment.TRUST_PROXY == "false");
    standalone-has-no-ingress-labels-or-app-publication = check "Standalone Pocket ID should publish only internal metrics and no Traefik labels."
      ((container active).labels == {} && (container active).ports == [ "9464:9464" ]);
    metrics-defaults-on = check "Pocket ID should enable Prometheus on its separate internal metrics port."
      ((container active).environment.OTEL_METRICS_EXPORTER == "prometheus"
        && ports active "metrics0" == [ 9464 ] && active.config.networking.firewall.allowedTCPPorts == []);
    metrics-custom-port-updates-all-contributions = check "Pocket ID metrics port should update listener, publication, firewall, and NFT filtering."
      ((container custom).ports == [ "19464:19464" ]
        && (container custom).environment.OTEL_EXPORTER_PROMETHEUS_PORT == "19464"
        && ports custom "metrics0" == [ 19464 ]
        && lib.hasInfix "19464" custom.config.networking.nftables.tables.pocket-id-exposure.content);
    metrics-restricts-incoming-interface = check "Pocket ID metrics should reject other ingress before Docker NAT."
      (lib.hasInfix ''iifname != { "metrics0" }'' active.config.networking.nftables.tables.pocket-id-exposure.content
        && lib.hasInfix "priority -110" active.config.networking.nftables.tables.pocket-id-exposure.content);
    metrics-opt-out-removes-support = check "Metrics opt-out should remove flags, publication, firewall, NFT, and its startup dependency."
      ((container metricsOptOut).ports == []
        && !((container metricsOptOut).environment ? OTEL_METRICS_EXPORTER)
        && !(metricsOptOut.config.networking.nftables.tables ? pocket-id-exposure)
        && ports metricsOptOut "metrics0" == []
        && !(builtins.elem "nftables.service" metricsOptOut.config.systemd.services.docker-pocket-id.requires));
    metrics-requires-nonempty-interfaces = check "Pocket ID metrics should reject an empty interface selection."
      (failedAssertion noMetricsInterfaces "Pocket ID metrics require a non-empty deployment.pocket-id.metricsInterfaces list, or set overrideMetricsIntegration = true.");
    metrics-requires-nftables = check "Pocket ID metrics should assert its NFT filtering requirement."
      (failedAssertion noNft "Pocket ID metrics interface restrictions require networking.nftables.enable.");
    requires-docker = check "Pocket ID should assert its Docker requirement."
      (failedAssertion noDocker "The Pocket ID container requires Docker.");
    requires-docker-backend = check "Pocket ID should assert its actual OCI backend."
      (failedAssertion podman "The Pocket ID container requires the Docker OCI backend.");
    native-traefik-container-activates-routing = check "Actual Traefik container presence should activate Pocket ID routing."
      ((container ingress).labels."traefik.enable" == "true"
        && (container ingress).labels."traefik.http.routers.pocket-id.rule" == "Host(`id.example.invalid`)");
    ingress-opt-out-removes-labels = check "Pocket ID's ingress opt-out should remove its automatic routing labels."
      ((container ingressOptOut).labels == {});
    local-ingress-requires-shared-network = check "Local ingress should assert the shared proxy-network requirement."
      (failedAssertion wrongNetwork "Pocket ID's local Traefik integration requires both containers on the proxy network. Attach both to proxy or set deployment.pocket-id.overrideTraefikIntegration = true.");
    tracing-defaults-on-with-alloy = check "Pocket ID should send traces through the shared Alloy receiver."
      ((container tracing).environment.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT == "http://172.30.0.1:4318/v1/traces"
        && tracing.config.environment.etc ? "alloy/traces.alloy");
    tracing-opt-out-preserves-metrics = check "Pocket ID tracing opt-out should remove tracing variables and preserve metrics."
      (!((container traceOptOut).environment ? OTEL_TRACES_EXPORTER)
        && (container traceOptOut).environment.OTEL_METRICS_EXPORTER == "prometheus");
    tracing-requires-proxy-network = check "Pocket ID tracing should assert network access to Alloy."
      (failedAssertion tracingWithoutNetwork "Pocket ID tracing through Alloy requires the proxy network. Attach Pocket ID to proxy or set deployment.pocket-id.overrideAlloyIntegration = true.");
    missing-domain-is-rejected = check "Pocket ID should require its deployment domain."
      (failsEvaluation (container (missing "domain")).environment.APP_URL);
    missing-data-volume-is-rejected = check "Pocket ID should require its storage assignment."
      (failsEvaluation (container (missing "dataVolume")).volumes);
    missing-secret-reference-is-rejected = check "Pocket ID should require its runtime credential reference."
      (failsEvaluation (container (missing "environmentFile")).environmentFiles);
    missing-smtp-is-rejected = check "Pocket ID should require deployment SMTP settings."
      (failsEvaluation (container (missing "smtp")).environment.SMTP_HOST);
    missing-trusted-proxies-is-rejected = check "Pocket ID should require explicit trusted-proxy selection, including an explicit empty list."
      (failsEvaluation (container (missing "trustedProxies")).environment.TRUST_PROXY);
  };
}
