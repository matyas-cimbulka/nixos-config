{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check;
  modules = config.flake.modules.nixos;
  dockerOnly = mkSystem [ modules.docker ] {};
  dockerDisabled = extend dockerOnly { virtualisation.docker.enable = false; };
  dockerBackendOverride = extend dockerOnly { virtualisation.oci-containers.backend = "podman"; };
in
{
  flake.lib.compositionTests.docker = {
    docker-enables-daemon = check "The Docker feature should enable Docker."
      dockerOnly.config.virtualisation.docker.enable;

    docker-defaults-to-docker-backend = check "Docker should select the Docker OCI backend."
      (dockerOnly.config.virtualisation.oci-containers.backend == "docker");

    docker-enable-is-overridable = check "Docker's enable default should be overridable."
      (!dockerDisabled.config.virtualisation.docker.enable);

    docker-backend-is-overridable = check "Docker's backend default should be overridable."
      (dockerBackendOverride.config.virtualisation.oci-containers.backend == "podman");

    docker-alone-does-not-enable-monitoring = check "Docker alone should not enable Alloy or cAdvisor."
      (!dockerOnly.config.services.alloy.enable && !dockerOnly.config.services.cadvisor.enable);
  };
}
