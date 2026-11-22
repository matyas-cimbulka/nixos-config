{
  flake.modules.nixos.mas =
    { config, lib, pkgs, ... }:
    let
      cfg = config.deployment.mas;
      inherit (config.virtualisation.oci-containers) containers;
      runtime = "/run/matrix-authentication";
      traefikEnabled = containers ? traefik && !cfg.overrideTraefikIntegration;
      settings = builtins.toFile "mas-base.yaml" (builtins.toJSON {
        http = {
          public_base = "https://${cfg.domain}/";
          listeners = [{
            name = "web";
            binds = [{ host = "0.0.0.0"; port = 8080; }];
            resources = map (name: { inherit name; }) [ "discovery" "human" "oauth" "compat" "graphql" "assets" ];
          }];
        };
        database = { host = "mas-postgres"; username = "mas"; database = "mas"; ssl_mode = "disable"; };
        matrix = {
          homeserver = cfg.serverName;
          endpoint = "http://synapse:8008";
          secret_file = "${runtime}/matrix-secret";
        };
        passwords.enabled = false;
        secrets = {
          encryption_file = "${runtime}/encryption";
          keys = [{ key_file = "${runtime}/signing.pem"; }];
        };
        upstream_oauth2.providers = [{
          id = cfg.providerId;
          human_name = "Pocket ID";
          issuer = cfg.issuer;
          client_id = cfg.clientId;
          client_secret_file = "${runtime}/oidc-secret";
          token_endpoint_auth_method = "client_secret_basic";
          scope = "openid profile email";
          claims_imports.localpart = { action = "require"; template = "{{ user.preferred_username }}"; };
        }];
      });
    in
    {
      options.deployment.mas = {
        domain = lib.mkOption { type = lib.types.str; };
        serverName = lib.mkOption { type = lib.types.str; };
        homeserverDomain = lib.mkOption { type = lib.types.str; };
        overrideTraefikIntegration = lib.mkEnableOption "disabling automatic local Traefik routes for MAS";
        dataDirectory = lib.mkOption { type = lib.types.strMatching "/.+"; };
        providerId = lib.mkOption { type = lib.types.strMatching "[0-9A-HJKMNP-TV-Z]{26}"; };
        issuer = lib.mkOption { type = lib.types.strMatching "https://.+"; };
        clientId = lib.mkOption { type = lib.types.nonEmptyStr; };
        clientSecretFile = lib.mkOption { type = lib.types.strMatching "/.+"; };
      };

      config = {
        assertions = [{
          assertion = config.virtualisation.docker.enable && config.virtualisation.oci-containers.backend == "docker";
          message = "MAS requires Docker and the Docker OCI backend.";
        } {
          assertion = !traefikEnabled || builtins.elem "proxy" containers.traefik.networks;
          message = "MAS's Traefik integration requires Traefik on the proxy network.";
        }];

        virtualisation.oci-containers.containers = {
          mas = {
            image = "ghcr.io/element-hq/matrix-authentication-service:1.29.0";
            networks = [ "proxy" "mas-db" ];
            dependsOn = [ "mas-postgres" ];
            volumes = [ "${runtime}/app:${runtime}:ro" ];
            cmd = [ "--config" "${runtime}/config.yaml" "server" ];
            labels = lib.mkIf traefikEnabled {
              "traefik.enable" = "true";
              "traefik.docker.network" = "proxy";
              "traefik.http.services.mas.loadbalancer.server.port" = "8080";
              "traefik.http.routers.mas.rule" = "Host(`${cfg.domain}`)";
              "traefik.http.routers.mas.entrypoints" = "websecure";
              "traefik.http.routers.mas.service" = "mas";
              "traefik.http.routers.mas-compat.rule" = "Host(`${cfg.homeserverDomain}`) && PathRegexp(`^/_matrix/client/(r0|v3|unstable)/(login|logout|logout/all|refresh)$`)";
              "traefik.http.routers.mas-compat.entrypoints" = "websecure";
              "traefik.http.routers.mas-compat.service" = "mas";
              "traefik.http.routers.mas-compat.priority" = "1000";
            };
          };
          mas-postgres = {
            image = "postgres:17.10-bookworm";
            networks = [ "mas-db" ];
            environment = {
              POSTGRES_USER = "mas";
              POSTGRES_DB = "mas";
              POSTGRES_PASSWORD_FILE = "${runtime}/database-password";
              POSTGRES_INITDB_ARGS = "--encoding=UTF8 --locale=C --auth-host=scram-sha-256";
            };
            volumes = [
              "${cfg.dataDirectory}/postgres:/var/lib/postgresql/data"
              "${runtime}/database-password:${runtime}/database-password:ro"
            ];
          };
        };

        systemd.services = let
          prerequisites = [ "mas-db-network.service" "mas-state.service" ];
        in {
          ${containers.mas.serviceName} = {
            requires = prerequisites;
            after = prerequisites;
            serviceConfig.RestartSec = "5s";
            preStart = ''
              install -m 0400 -o 65532 -g 65532 ${lib.escapeShellArg cfg.clientSecretFile} ${runtime}/app/oidc-secret
            '';
          };
          ${containers.mas-postgres.serviceName} = {
            requires = prerequisites;
            after = prerequisites;
          };
          mas-db-network = {
            requires = [ "docker.service" ];
            after = [ "docker.service" ];
            path = [ pkgs.docker ];
            serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
            script = ''
              if ! docker network inspect mas-db >/dev/null 2>&1; then
                docker network create --internal mas-db
              fi
              test "$(docker network inspect -f '{{.Internal}}' mas-db)" = true
            '';
          };
          mas-state = {
            unitConfig.RequiresMountsFor = [ cfg.dataDirectory ];
            path = [ pkgs.openssl pkgs.jq ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              RuntimeDirectory = "matrix-authentication";
              RuntimeDirectoryMode = "0700";
              UMask = "0077";
            };
            script = ''
              state=${lib.escapeShellArg cfg.dataDirectory}
              install -d -m 0700 "$state/secrets"
              install -d -m 0700 -o 999 -g 999 "$state/postgres"
              install -d -m 0700 -o 65532 -g 65532 ${runtime}/app
              for key in database-password matrix-secret encryption signing.pem; do
                file="$state/secrets/$key"
                if [ ! -s "$file" ]; then
                  if [ -e "$state/postgres/PG_VERSION" ]; then
                    echo "Missing MAS $key for existing database; restore it from backup." >&2
                    exit 1
                  fi
                  temp=$(mktemp "$state/secrets/$key.XXXXXXXX")
                  if [ "$key" = signing.pem ]; then
                    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 > "$temp"
                  else
                    openssl rand -hex 32 > "$temp"
                  fi
                  mv "$temp" "$file"
                fi
                if [ "$key" = database-password ]; then
                  install -m 0400 -o 999 -g 999 "$file" "${runtime}/$key"
                elif [ "$key" = encryption ]; then
                  # MAS decodes the whole file as hex, including any trailing newline.
                  temp=$(mktemp "${runtime}/encryption.XXXXXXXX")
                  printf '%s' "$(<"$file")" > "$temp"
                  install -m 0400 -o 65532 -g 65532 "$temp" "${runtime}/app/$key"
                  rm "$temp"
                else
                  install -m 0400 -o 65532 -g 65532 "$file" "${runtime}/app/$key"
                fi
              done
              install -m 0400 -o 991 -g 991 "$state/secrets/matrix-secret" ${runtime}/synapse-secret
              jq --rawfile password "$state/secrets/database-password" \
                '.database.password = ($password | rtrimstr("\n"))' ${settings} > ${runtime}/app/config.yaml
              chown 65532:65532 ${runtime}/app/config.yaml
            '';
          };
        };
      };
    };
}
