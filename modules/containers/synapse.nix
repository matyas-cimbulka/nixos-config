{
  flake.modules.nixos.synapse =
    { config, lib, pkgs, ... }:
    let
      cfg = config.deployment.synapse;
      containers = config.virtualisation.oci-containers.containers;
      traefikEnabled = containers ? traefik && !cfg.overrideTraefikIntegration;
      credentials = "/run/matrix-db";
      masEnabled = cfg.mas != null;
      databaseHost = "matrix-postgres";
      appServices = lib.imap0 (index: registration: registration // {
        target = "/etc/synapse/appservice-${toString index}.json";
      }) cfg.appServices;
      settings = builtins.toFile "synapse-homeserver.yaml" (builtins.toJSON ({
        server_name = cfg.serverName;
        public_baseurl = "https://${cfg.domain}/";
        listeners = [{
          port = 8008;
          type = "http";
          tls = false;
          x_forwarded = true;
          resources = [{ names = [ "client" ]; }];
        }];
        signing_key_path = "/data/homeserver.signing.key";
        media_store_path = "/data/media_store";
        database = {
          name = "psycopg2";
          args = {
            host = databaseHost;
            user = "synapse";
            database = "synapse";
            passfile = "${credentials}/pgpass";
          };
        };
        federation_domain_whitelist = [ ];
        trusted_key_servers = [ ];
        enable_registration = false;
        allow_guest_access = false;
        password_config.enabled = false;
        url_preview_enabled = false;
        report_stats = false;
        push.include_content = false;
        app_service_config_files = map (registration: registration.target) appServices;
      } // lib.optionalAttrs masEnabled {
        matrix_authentication_service = {
          enabled = true;
          endpoint = cfg.mas.endpoint;
          secret_path = "/run/synapse/mas-secret";
        };
        experimental_features = {
          msc4108_enabled = true;
          msc4388_mode = "authenticated";
        };
      }));
      databaseInit = builtins.toFile "matrix-postgres-init.sh" ''
        (
          SYNAPSE_DB_PASSWORD="$(cat /run/matrix-db/synapse-password)"
          export SYNAPSE_DB_PASSWORD
          psql --username postgres --dbname postgres --no-password --set ON_ERROR_STOP=1 <<'SQL'
        \getenv synapse_password SYNAPSE_DB_PASSWORD
        CREATE USER synapse WITH PASSWORD :'synapse_password';
        CREATE DATABASE synapse OWNER synapse;
        SQL
        )
      '';
    in
    {
      options.deployment.synapse = {
        serverName = lib.mkOption {
          type = lib.types.str;
          description = "Matrix ID domain. Do not change it after initializing the homeserver.";
        };
        domain = lib.mkOption {
          type = lib.types.str;
          description = "HTTPS hostname of the Synapse client API.";
        };
        dataDirectory = lib.mkOption {
          type = lib.types.strMatching "/.+";
          description = "Persistent host directory for Synapse signing keys and media.";
        };
        databaseDirectory = lib.mkOption {
          type = lib.types.strMatching "/.+";
          description = "Persistent host directory for PostgreSQL data and its generated credentials.";
        };
        appServices = lib.mkOption {
          type = lib.types.listOf (lib.types.submodule {
            options = {
              file = lib.mkOption { type = lib.types.strMatching "/.+"; };
              service = lib.mkOption { type = lib.types.strMatching ".+\\.service"; };
            };
          });
          default = [ ];
          description = "Runtime application service registrations and their generating units.";
        };
        mas = lib.mkOption {
          type = lib.types.nullOr (lib.types.submodule {
            options = {
              endpoint = lib.mkOption { type = lib.types.strMatching "https?://.+"; };
              secretFile = lib.mkOption { type = lib.types.strMatching "/.+"; };
              secretService = lib.mkOption { type = lib.types.strMatching ".+\\.service"; };
            };
          });
          default = null;
          description = "Matrix Authentication Service endpoint and runtime shared-secret delivery.";
        };
        overrideTraefikIntegration = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable routing the client API through the local Traefik container.";
        };
      };

      config = {
        assertions = [
          {
            assertion = config.virtualisation.docker.enable && config.virtualisation.oci-containers.backend == "docker";
            message = "Synapse and its PostgreSQL container require Docker and the Docker OCI backend.";
          }
          {
            assertion = !traefikEnabled || builtins.elem "proxy" containers.traefik.networks;
            message = "Synapse's Traefik integration requires the Traefik container on the proxy network.";
          }
        ];

        virtualisation.oci-containers.containers = {
          synapse = {
            image = "matrixdotorg/synapse:v1.163.0";
            networks = [ "matrix-db" ] ++ lib.optional traefikEnabled "proxy";
            dependsOn = [ databaseHost ];
            environment.SYNAPSE_CONFIG_PATH = "/etc/synapse/homeserver.yaml";
            volumes = [
              "${settings}:/etc/synapse/homeserver.yaml:ro"
              "${cfg.dataDirectory}:/data"
              "${credentials}/pgpass:${credentials}/pgpass:ro"
            ] ++ lib.optional masEnabled "${cfg.mas.secretFile}:/run/synapse/mas-secret:ro"
              ++ map (registration: "${registration.file}:${registration.target}:ro") appServices;
            labels = lib.mkIf traefikEnabled {
              "traefik.enable" = "true";
              "traefik.docker.network" = "proxy";
              "traefik.http.routers.synapse.rule" = "Host(`${cfg.domain}`) && (PathPrefix(`/_matrix/client/`) || PathPrefix(`/_matrix/media/`)${lib.optionalString masEnabled " || PathPrefix(`/_synapse/client/rendezvous/`)"})";
              "traefik.http.routers.synapse.entrypoints" = "websecure";
              "traefik.http.services.synapse.loadbalancer.server.port" = "8008";
            };
          };
          ${databaseHost} = {
            image = "postgres:17.10-bookworm";
            networks = [ "matrix-db" ];
            environment = {
              POSTGRES_PASSWORD_FILE = "${credentials}/postgres-password";
              POSTGRES_INITDB_ARGS = "--encoding=UTF8 --locale=C --auth-local=peer --auth-host=scram-sha-256";
            };
            volumes = [
              "${cfg.databaseDirectory}/data:/var/lib/postgresql/data"
              "${credentials}/postgres-password:${credentials}/postgres-password:ro"
              "${credentials}/synapse-password:${credentials}/synapse-password:ro"
              "${databaseInit}:/docker-entrypoint-initdb.d/synapse.sh:ro"
            ];
          };
        };

        systemd.services = let
          prerequisites = {
            requires = [ "matrix-db-network.service" "matrix-db-credentials.service" ];
            after = [ "matrix-db-network.service" "matrix-db-credentials.service" ];
          };
        in {
          ${containers.${databaseHost}.serviceName} = prerequisites;
          # Docker startup ordering does not wait for PostgreSQL initialization.
          ${containers.synapse.serviceName} = lib.mkMerge [ prerequisites {
            serviceConfig.RestartSec = "5s";
            requires = map (registration: registration.service) appServices;
            after = map (registration: registration.service) appServices;
          } (lib.mkIf masEnabled {
            requires = [ cfg.mas.secretService ];
            after = [ cfg.mas.secretService ];
          }) ];

          matrix-db-network = {
            description = "Create the private Matrix database Docker network";
            requires = [ "docker.service" ];
            after = [ "docker.service" ];
            path = [ pkgs.docker ];
            serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
            script = ''
              if ! docker network inspect matrix-db >/dev/null 2>&1; then
                docker network create --internal matrix-db
              fi
              test "$(docker network inspect -f '{{.Internal}}' matrix-db)" = true
            '';
          };
          matrix-db-credentials = {
            description = "Initialize persistent Matrix data directories and database credentials";
            unitConfig.RequiresMountsFor = [ cfg.databaseDirectory cfg.dataDirectory ];
            path = [ pkgs.openssl ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              RuntimeDirectory = "matrix-db";
              RuntimeDirectoryMode = "0700";
              UMask = "0077";
            };
            script = ''
              database=${lib.escapeShellArg cfg.databaseDirectory}
              install -d -m 0700 "$database/credentials"
              install -d -m 0700 -o 999 -g 999 "$database/data"
              install -d -m 0700 -o 991 -g 991 ${lib.escapeShellArg cfg.dataDirectory}

              for role in postgres synapse; do
                password="$database/credentials/$role-password"
                if [ ! -s "$password" ]; then
                  if [ -e "$database/data/PG_VERSION" ]; then
                    echo "Missing $role credential for existing Matrix database; restore it from backup." >&2
                    exit 1
                  fi
                  temp=$(mktemp "$database/credentials/$role.XXXXXXXX")
                  openssl rand -hex 32 > "$temp"
                  mv "$temp" "$password"
                fi
                install -m 0400 -o 999 -g 999 "$password" "${credentials}/$role-password"
              done

              printf '%s:5432:synapse:synapse:%s\n' '${databaseHost}' "$(cat "$database/credentials/synapse-password")" > ${credentials}/pgpass
              chown 991:991 ${credentials}/pgpass
            '';
          };
        };
      };
    };
}
