{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check ports failedAssertion failsEvaluation cadvisorInactive;
  modules = config.flake.modules.nixos;
  cadvisorWithoutDocker = mkSystem [ modules.cadvisor ] {
    deployment.cadvisor.metricsInterface = "test0";
  };
  cadvisorStandalone = extend cadvisorWithoutDocker { virtualisation.docker.enable = true; };
  cadvisorDisabled = mkSystem [ modules.cadvisor ] { services.cadvisor.enable = false; };
  cadvisorOptOut = mkSystem [ modules.cadvisor ] {
    deployment.cadvisor.overrideIntegration = true;
  };
  cadvisorExplicitlyDisabled = extend cadvisorStandalone { services.cadvisor.enable = false; };
  cadvisorCustom = extend cadvisorStandalone {
    services.cadvisor = { port = 9081; listenAddress = "127.0.0.1"; };
    deployment.cadvisor.metricsInterface = lib.mkForce "metrics0";
  };
  missingCadvisorInterface = mkSystem [ modules.cadvisor ] {
    virtualisation.docker.enable = true;
  };
in
{
  flake.lib.compositionTests.cadvisor = {
    cadvisor-opens-metrics-port =
      assert lib.assertMsg (builtins.elem 8081 cadvisorStandalone.config.networking.firewall.interfaces.test0.allowedTCPPorts)
        "Active cAdvisor should open its metrics port on test0 interface.";
      true;

    cadvisor-orders-after-docker = check "cAdvisor should require Docker and start after it."
      (builtins.elem "docker.service" cadvisorStandalone.config.systemd.services.cadvisor.requires
        && builtins.elem "docker.service" cadvisorStandalone.config.systemd.services.cadvisor.after);

    cadvisor-has-no-failed-docker-assertion = check "Docker should satisfy cAdvisor's prerequisite."
      (!(failedAssertion cadvisorStandalone "The cAdvisor feature requires Docker."));

    cadvisor-requires-docker = check "cAdvisor without Docker should declare its prerequisite failure."
      (failedAssertion cadvisorWithoutDocker "The cAdvisor feature requires Docker.");

    cadvisor-can-run-without-alloy = check "Standalone cAdvisor should work with native Docker enabled."
      (cadvisorStandalone.config.services.cadvisor.enable
        && !cadvisorStandalone.config.services.alloy.enable
        && builtins.elem 8081 (ports cadvisorStandalone "test0")
        && !(failedAssertion cadvisorStandalone "The cAdvisor feature requires Docker."));

    cadvisor-uses-configured-port-and-interface = check "cAdvisor's firewall opening should follow deployment values."
      (builtins.elem 9081 (ports cadvisorCustom "metrics0")
        && !(builtins.elem 8081 (ports cadvisorCustom "metrics0"))
        && !(builtins.elem 9081 (ports cadvisorCustom "test0"))
        && !(builtins.elem 9081 cadvisorCustom.config.networking.firewall.allowedTCPPorts)
        && cadvisorCustom.config.services.cadvisor.listenAddress == "127.0.0.1");

    cadvisor-does-not-open-global-port = check "cAdvisor's metrics opening should be interface-specific."
      (!(builtins.elem 8081 cadvisorStandalone.config.networking.firewall.allowedTCPPorts));

    cadvisor-explicit-disable-removes-support = check "Disabling cAdvisor should remove its supporting configuration."
      (cadvisorInactive cadvisorExplicitlyDisabled);

    standalone-cadvisor-disable-needs-no-deployment = check "Disabled cAdvisor should need neither Docker nor an interface."
      (cadvisorInactive cadvisorDisabled
        && !(failedAssertion cadvisorDisabled "The cAdvisor feature requires Docker."));

    standalone-cadvisor-opt-out-needs-no-deployment = check "Opted-out cAdvisor should need neither Docker nor an interface."
      (cadvisorInactive cadvisorOptOut
        && !(failedAssertion cadvisorOptOut "The cAdvisor feature requires Docker."));

    active-cadvisor-requires-interface = check "Active cAdvisor should reject a missing metrics interface."
      (failsEvaluation missingCadvisorInterface.config.networking.firewall.interfaces);
  };
}
