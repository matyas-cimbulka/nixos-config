{
  flake.modules.nixos.hookshot =
    { config, lib, pkgs, ... }:
    let
      cfg = config.deployment.hookshot;
      runtime = "/run/hookshot";
      service = "hookshot-state.service";
      registration = builtins.toFile "hookshot-registration.json" (builtins.toJSON {
        id = "hookshot";
        sender_localpart = "_hookshot";
        url = "http://hookshot:9993";
        rate_limited = false;
        namespaces = {
          users = [{ regex = "^@_hookshot(?:_.*)?:${lib.escapeRegex cfg.serverName}$"; exclusive = true; }];
          rooms = [ ];
          aliases = [ ];
        };
      });
      settings = builtins.toFile "hookshot-config.json" (builtins.toJSON {
        bridge = { domain = cfg.serverName; url = "http://synapse:8008"; port = 9993; bindAddress = "0.0.0.0"; };
        passFile = "/data/passkey.pem";
        listeners = [{ port = 9000; bindAddress = "0.0.0.0"; resources = [ "webhooks" ]; }];
        generic = {
          enabled = true;
          outbound = false;
          urlPrefix = cfg.webhookUrlPrefix;
          userIdPrefix = "_hookshot_";
          allowJsTransformationFunctions = false;
          waitForComplete = true;
          enableHttpGet = false;
        };
        permissions = [{ actor = cfg.operator; services = [{ service = "generic"; level = "manageConnections"; }]; }];
      });
    in
    {
      options.deployment.hookshot = {
        serverName = lib.mkOption { type = lib.types.nonEmptyStr; description = "Matrix ID domain."; };
        operator = lib.mkOption { type = lib.types.nonEmptyStr; description = "Matrix user permitted to manage webhook connections."; };
        dataDirectory = lib.mkOption { type = lib.types.strMatching "/.+"; description = "Persistent directory for Hookshot keys."; };
        webhookLoopbackPort = lib.mkOption {
          type = lib.types.nullOr lib.types.port;
          default = null;
          description = "Optional IPv4 loopback host port for the webhook listener only.";
        };
        webhookUrlPrefix = lib.mkOption { type = lib.types.strMatching "https?://.+/webhook/"; description = "Webhook URL prefix returned to the operator."; };
      };

      config = {
        assertions = [{
          assertion = config.virtualisation.docker.enable && config.virtualisation.oci-containers.backend == "docker";
          message = "Hookshot requires Docker and the Docker OCI backend.";
        }];
        deployment.synapse.appServices = [{ file = "${runtime}/registration.json"; inherit service; }];
        virtualisation.oci-containers.containers.hookshot = {
          image = "ghcr.io/matrix-org/matrix-hookshot:7.6.2";
          networks = [ "proxy" ];
          dependsOn = [ "synapse" ];
          ports = lib.optional (cfg.webhookLoopbackPort != null) "127.0.0.1:${toString cfg.webhookLoopbackPort}:9000";
          volumes = [
            "${settings}:/data/config.yml:ro"
            "${runtime}/registration.json:/data/registration.yml:ro"
            "${cfg.dataDirectory}/passkey.pem:/data/passkey.pem:ro"
          ];
        };
        systemd.services = {
          ${config.virtualisation.oci-containers.containers.hookshot.serviceName} = {
            requires = [ service ];
            after = [ service ];
            serviceConfig.RestartSec = "5s";
          };
          hookshot-state = {
            unitConfig.RequiresMountsFor = [ cfg.dataDirectory ];
            path = [ pkgs.openssl pkgs.jq ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              RuntimeDirectory = "hookshot";
              RuntimeDirectoryMode = "0700";
              UMask = "0077";
            };
            script = ''
              state=${lib.escapeShellArg cfg.dataDirectory}
              if [ ! -e "$state/passkey.pem" ]; then
                openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 > "$state/passkey.tmp"
                mv "$state/passkey.tmp" "$state/passkey.pem"
              fi
              for token in as_token hs_token; do
                if [ ! -e "$state/$token" ]; then
                  openssl rand -hex 32 > "$state/$token.tmp"
                  mv "$state/$token.tmp" "$state/$token"
                fi
              done
              jq --rawfile as "$state/as_token" --rawfile hs "$state/hs_token" \
                '.as_token = ($as | rtrimstr("\n")) | .hs_token = ($hs | rtrimstr("\n"))' \
                ${registration} > ${runtime}/registration.json
              chown 991:991 ${runtime}/registration.json
            '';
          };
        };
      };
    };
}
