{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check failsEvaluation failedAssertion;
  modules = config.flake.modules.nixos;
  settings = {
    virtualisation.docker.enable = true;
    virtualisation.oci-containers = {
      backend = "docker";
      containers = {
        sample = { image = "example.invalid/sample:test"; serviceName = "custom-sample"; };
        isolated = { image = "example.invalid/isolated:test"; networks = [ "private" ]; };
      };
    };
    deployment.docker-proxy = { subnet = "172.30.0.0/24"; gateway = "172.30.0.1"; };
  };
  active = mkSystem [ modules.docker-proxy ] settings;
  disabled = mkSystem [ modules.docker-proxy ] {
    deployment.docker-proxy.enable = false;
    virtualisation.oci-containers.containers.sample.image = "example.invalid/sample:test";
  };
  noDocker = extend active { virtualisation.docker.enable = lib.mkForce false; };
  podman = extend active { virtualisation.oci-containers.backend = lib.mkForce "podman"; };
  missingSubnet = mkSystem [ modules.docker-proxy ] {
    virtualisation.docker.enable = true;
    deployment.docker-proxy.gateway = "172.30.0.1";
  };
  missingGateway = mkSystem [ modules.docker-proxy ] {
    virtualisation.docker.enable = true;
    deployment.docker-proxy.subnet = "172.30.0.0/24";
  };
in
{
  flake.lib.compositionTests.docker-proxy = {
    attaches-containers-by-default = check "docker-proxy should attach OCI containers to proxy by default."
      (active.config.virtualisation.oci-containers.containers.sample.networks == [ "proxy" ]);
    explicit-network-selection-wins = check "Explicit container networks should replace the automatic proxy default."
      (active.config.virtualisation.oci-containers.containers.isolated.networks == [ "private" ]);
    uses-effective-service-name = check "Proxy startup ordering should use the container's configured service name."
      (builtins.elem "docker-network-proxy.service" active.config.systemd.services.custom-sample.requires
        && builtins.elem "docker-network-proxy.service" active.config.systemd.services.custom-sample.after);
    isolated-container-has-no-proxy-dependency = check "A container outside proxy should not depend on that network."
      (!(builtins.elem "docker-network-proxy.service" active.config.systemd.services.docker-isolated.requires));
    network-creation-uses-deployment = check "Proxy creation should consume supplied subnet, gateway, and bridge name."
      (lib.all (fragment: lib.hasInfix fragment active.config.systemd.services.docker-network-proxy.script)
        [ "172.30.0.0/24" "172.30.0.1" "docker-proxy" ]);
    requires-docker = check "docker-proxy should assert its Docker daemon requirement."
      (failedAssertion noDocker "The docker-proxy network requires Docker.");
    requires-docker-backend = check "docker-proxy should assert the actual OCI backend."
      (failedAssertion podman "The docker-proxy network requires the Docker OCI backend.");
    missing-subnet-is-rejected = check "Enabled docker-proxy should require its subnet."
      (failsEvaluation missingSubnet.config.systemd.services.docker-network-proxy.script);
    missing-gateway-is-rejected = check "Enabled docker-proxy should require its gateway."
      (failsEvaluation missingGateway.config.systemd.services.docker-network-proxy.script);
    disable-removes-network-support = check "Disabled docker-proxy should need no deployment and leave container networks alone."
      (!(disabled.config.systemd.services ? docker-network-proxy)
        && disabled.config.virtualisation.oci-containers.containers.sample.networks == []
        && !(builtins.elem "docker-network-proxy.service" disabled.config.systemd.services.podman-sample.requires));
  };
}
