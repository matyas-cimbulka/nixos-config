{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check ports failsEvaluation;
  modules = config.flake.modules.nixos;
  active = mkSystem [ modules.loki ] { deployment.loki.interfaces = [ "logs0" ]; };
  disabled = mkSystem [ modules.loki ] { services.loki.enable = false; };
  missingInterface = mkSystem [ modules.loki ] {};
  custom = extend active {
    services.loki = { dataDir = "/var/lib/custom-loki"; configuration.server.http_listen_port = 13100; };
  };
in
{
  flake.lib.compositionTests.loki = {
    enables-service = check "The Loki feature should enable Loki." active.config.services.loki.enable;
    interface-specific-port = check "Loki HTTP should open only on its configured interface."
      (builtins.elem 3100 (ports active "logs0") && active.config.networking.firewall.allowedTCPPorts == []);
    custom-port-follows-listener = check "Loki's firewall should follow its effective HTTP port."
      (ports custom "logs0" == [ 13100 ]);
    storage-follows-data-directory = check "Loki storage paths should follow its configured data directory."
      (custom.config.services.loki.configuration.common.storage.filesystem.chunks_directory == "/var/lib/custom-loki/chunks"
        && custom.config.services.loki.configuration.storage_config.tsdb_shipper.active_index_directory == "/var/lib/custom-loki/index");
    grpc-stays-local = check "Loki's internal gRPC listener should remain local."
      (active.config.services.loki.configuration.server.grpc_listen_address == "127.0.0.1");
    missing-interface-is-rejected = check "Active Loki should require explicitly supplied deployment interfaces."
      (failsEvaluation missingInterface.config.networking.firewall.interfaces);
    disable-removes-support = check "Disabled Loki should need no deployment and leave no unit or firewall contributions."
      (!disabled.config.services.loki.enable && !(disabled.config.systemd.services ? loki)
        && disabled.config.networking.firewall.interfaces == {}
        && disabled.config.services.loki.configuration == {});
  };
}
