{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check ports failsEvaluation;
  modules = config.flake.modules.nixos;
  selected = mkSystem [ modules.tempo ] {};
  # Explicit enable reaches the settings even if the feature's enable default regresses.
  active = extend selected {
    services.tempo.enable = true;
    deployment.tempo = { apiInterfaces = [ "api0" ]; otlpInterfaces = [ "ingest0" ]; };
  };
  custom = extend active {
    services.tempo.settings.server.http_listen_port = 13200;
    deployment.tempo.otlpPort = 14317;
  };
  shared = extend active { deployment.tempo.otlpInterfaces = lib.mkForce [ "api0" ]; };
  disabled = extend selected { services.tempo.enable = false; };
  missingApi = mkSystem [ modules.tempo ] {
    services.tempo.enable = true;
    deployment.tempo.otlpInterfaces = [ "ingest0" ];
  };
  missingOtlp = mkSystem [ modules.tempo ] {
    services.tempo.enable = true;
    deployment.tempo.apiInterfaces = [ "api0" ];
  };
in
{
  flake.lib.compositionTests.tempo = {
    explicit-empty-interfaces-is-accepted = check "Explicit empty Tempo interface lists should contribute no API or OTLP openings."
      ((extend active { deployment.tempo = { apiInterfaces = lib.mkForce []; otlpInterfaces = lib.mkForce []; }; }).config.networking.firewall.interfaces == {});
    enables-service = check "Importing the Tempo feature should enable Tempo." selected.config.services.tempo.enable;
    separates-api-and-ingestion = check "Tempo API and OTLP exposure should use independent interfaces."
      (ports active "api0" == [ 3200 ] && ports active "ingest0" == [ 4317 ]
        && active.config.networking.firewall.allowedTCPPorts == []);
    merges-shared-interface = check "Tempo should retain both ports when API and ingestion share an interface."
      (builtins.elem 3200 (ports shared "api0") && builtins.elem 4317 (ports shared "api0"));
    custom-ports-follow-listeners = check "Tempo's published firewall ports and receiver should follow configured ports."
      (ports custom "api0" == [ 13200 ] && ports custom "ingest0" == [ 14317 ]
        && custom.config.services.tempo.settings.distributor.receivers.otlp.protocols.grpc.endpoint == "0.0.0.0:14317");
    owns-service-identity = check "Tempo should use its declared service identity and private state directory."
      (!active.config.systemd.services.tempo.serviceConfig.DynamicUser
        && active.config.systemd.services.tempo.serviceConfig.User == "tempo"
        && active.config.users.users.tempo.isSystemUser
        && active.config.systemd.services.tempo.serviceConfig.StateDirectoryMode == "0750");
    missing-api-interface-is-rejected = check "Active Tempo should require explicit API interfaces."
      (failsEvaluation missingApi.config.networking.firewall.interfaces);
    missing-otlp-interface-is-rejected = check "Active Tempo should require explicit OTLP interfaces."
      (failsEvaluation missingOtlp.config.networking.firewall.interfaces);
    disable-removes-support = check "Disabled Tempo should need no deployment values or leave custom support."
      (!(disabled.config.systemd.services ? tempo) && !(disabled.config.users.users ? tempo)
        && disabled.config.networking.firewall.interfaces == {}
        && disabled.config.services.tempo.settings == {});
  };
}
