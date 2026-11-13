{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check ports failsEvaluation failedAssertion;
  modules = config.flake.modules.nixos;
  selected = [ modules.docker modules.docker-proxy modules.traefik ];
  settings.deployment = {
    docker-proxy = { subnet = "172.30.0.0/24"; gateway = "172.30.0.1"; };
    traefik = {
      portsByInterface = { lan0 = [ 80 443 ]; tailscale0 = [ 443 8080 ]; };
      dnsServer = "1.1.1.1"; acmeEmail = "admin@example.invalid";
      environmentFile = "/run/test-secrets/cloudflare.env";
    };
  };
  active = mkSystem selected settings;
  # Native OCI containers normally enable Docker themselves; force an invalid fixture.
  noDocker = extend active { virtualisation.docker.enable = lib.mkForce false; };
  noProxy = extend active { deployment.docker-proxy.enable = false; };
  podman = extend active { virtualisation.oci-containers.backend = "podman"; };
  noNft = extend active { networking.nftables.enable = false; };
  tracing = extend active {
    imports = [ modules.alloy ];
    deployment = {
      cadvisor.metricsInterface = "metrics0";
      alloy = { httpInterfaces = [ "metrics0" ]; overrideLokiIntegration = true; tempoEndpoint = "tempo.example.invalid:4317"; };
    };
  };
  traceOptOut = extend tracing { deployment.traefik.overrideAlloyIntegration = true; };
  missing = name: mkSystem selected (settings // {
    deployment = settings.deployment // { traefik = builtins.removeAttrs settings.deployment.traefik [ name ]; };
  });
  restricted = extend active { deployment.traefik.portsByInterface = lib.mkForce { tailscale0 = [ 443 ]; }; };
  dynamic = extend active { deployment.traefik.dynamicConfig.http.routers.test.rule = "Host(`example.invalid`)"; };
  container = configuration: configuration.config.virtualisation.oci-containers.containers.traefik;
in
{
  flake.lib.compositionTests.traefik = {
    explicit-empty-exposure-publishes-no-ports = check "An explicit empty Traefik exposure selection should publish no ports and retain drop rules."
      (let empty = extend active { deployment.traefik.portsByInterface = lib.mkForce {}; };
       in (container empty).ports == [] && empty.config.networking.firewall.interfaces == {}
         && lib.all (port: lib.hasInfix "tcp dport ${toString port} counter drop"
           empty.config.networking.nftables.tables.traefik-exposure.content) [ 80 443 8080 ]);
    publishes-only-selected-ports = check "Traefik should publish the unique union of explicitly permitted ports."
      (lib.sort builtins.lessThan (container active).ports == [ "443:443" "8080:8080" "80:80" ]);
    firewall-follows-per-interface-selection = check "Traefik firewall openings should preserve per-interface port selection."
      (ports active "lan0" == [ 80 443 ] && ports active "tailscale0" == [ 443 8080 ]
        && active.config.networking.firewall.allowedTCPPorts == []);
    unpublished-ports-still-denied-before-dnat = check "Traefik should deny unselected ports and restrict selected ingress before Docker NAT."
      ((container restricted).ports == [ "443:443" ]
        && lib.hasInfix "tcp dport 80 counter drop" restricted.config.networking.nftables.tables.traefik-exposure.content
        && lib.hasInfix ''tcp dport 443 iifname != { "tailscale0" } counter drop'' restricted.config.networking.nftables.tables.traefik-exposure.content
        && lib.hasInfix "tcp dport 8080 counter drop" restricted.config.networking.nftables.tables.traefik-exposure.content
        && lib.hasInfix "priority -110" restricted.config.networking.nftables.tables.traefik-exposure.content);
    uses-runtime-secret-reference = check "Traefik should consume the supplied credential file without owning delivery."
      ((container active).environmentFiles == [ "/run/test-secrets/cloudflare.env" ]
        && !(active.config.systemd.services.docker-traefik.serviceConfig ? ImportCredential));
    optional-dynamic-config-evaluates = check "Traefik should evaluate both empty and explicitly supplied dynamic configuration."
      (builtins.deepSeq (container active).volumes true && builtins.deepSeq (container dynamic).volumes true);
    requires-docker = check "Traefik should assert its Docker requirement."
      (failedAssertion noDocker "The Traefik container requires Docker.");
    requires-docker-backend = check "Traefik should assert its actual OCI backend."
      (failedAssertion podman "The Traefik container requires `docker` backend.");
    requires-proxy-network = check "Traefik should assert the proxy-network capability."
      (failedAssertion noProxy "The Traefik container requires the `docker-proxy` network feature.");
    requires-nftables = check "Traefik should assert its NFT filtering requirement."
      (failedAssertion noNft "Traefik interface restrictions require networking.nftables.enable.");
    tracing-defaults-on-with-alloy = check "Traefik should trace through Alloy using the deployed proxy gateway."
      (builtins.elem "--tracing.otlp.http.endpoint=http://172.30.0.1:4318/v1/traces" (container tracing).cmd
        && tracing.config.environment.etc ? "alloy/traces.alloy");
    tracing-opt-out-removes-both-sides = check "Traefik tracing opt-out should remove its flags and the unused Alloy receiver."
      (!(lib.any (flag: lib.hasPrefix "--tracing." flag) (container traceOptOut).cmd)
        && !(traceOptOut.config.environment.etc ? "alloy/traces.alloy")
        && ports traceOptOut "docker-proxy" == []);
    without-alloy-has-no-tracing = check "Traefik should run without Alloy and contribute no tracing flags."
      (!(lib.any (flag: lib.hasPrefix "--tracing." flag) (container active).cmd));
    missing-dns-server-is-rejected = check "Traefik should require deployment DNS."
      (failsEvaluation (container (missing "dnsServer")).extraOptions);
    missing-acme-email-is-rejected = check "Traefik should require its ACME contact."
      (failsEvaluation (container (missing "acmeEmail")).cmd);
    missing-secret-path-is-rejected = check "Traefik should require its runtime credential reference."
      (failsEvaluation (container (missing "environmentFile")).environmentFiles);
    missing-exposure-selection-is-rejected = check "Traefik should require explicit exposure selection."
      (failsEvaluation (container (missing "portsByInterface")).ports);
  };
}
