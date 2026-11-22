{
  flake.modules.nixos.teleport-control-plane =
    { config, lib, options, pkgs, ... }:
    let
      cfg = config.deployment.teleport-control-plane;
      containers = config.virtualisation.oci-containers.containers;
      hasTraefikTransport = options ? deployment.traefik.dynamicConfig;
      traefikIntegrationEnabled = hasTraefikTransport && !cfg.overrideTraefikIntegration;
      originDirectory = "/run/teleport-origin-tls";
      trustFile = "/etc/traefik/teleport-origin.pem";
      # A document marker tells Teleport's YAML-or-JSON decoder this is a YAML stream.
      startupResources = builtins.toFile "teleport-enrollment.json" (
        "---\n" + lib.concatMapStringsSep "\n---\n" builtins.toJSON cfg.startupResources
      );
      containerResources = "/etc/teleport/enrollment.json";
      applyStartupResources = cfg.startupResources != [];
      originDependency = {
        requires = [ "teleport-origin-tls.service" ];
        after = [ "teleport-origin-tls.service" ];
      };
      # Teleport accepts JSON as YAML; toFile keeps the non-secret config directly inspectable.
      configFile = builtins.toFile "teleport.yaml" (builtins.toJSON {
        version = "v3";
        auth_service = {
          enabled = true;
          listen_addr = "127.0.0.1:3025";
          cluster_name = cfg.domain;
          proxy_listener_mode = "multiplex";
          authentication = {
            type = "local";
            second_factors = [ "webauthn" ];
            passwordless = true;
            connector_name = "passwordless";
            webauthn.rp_id = cfg.domain;
          };
        };
        proxy_service = {
          enabled = true;
          web_listen_addr = "0.0.0.0:3080";
          public_addr = "${cfg.domain}:443";
        } // lib.optionalAttrs traefikIntegrationEnabled {
          https_keypairs = [{ cert_file = "/etc/teleport/origin/cert.pem"; key_file = "/etc/teleport/origin/key.pem"; }];
        };
        ssh_service.enabled = false;
      });
    in
    {
      options.deployment.teleport-control-plane = {
        overrideTraefikIntegration = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Disable automatic HTTPS routing through the local Traefik container.";
        };
        domain = lib.mkOption {
          type = lib.types.strMatching "[a-z0-9-]+(\\.[a-z0-9-]+)+";
          description = "Public DNS hostname of the Teleport proxy and WebAuthn relying party.";
        };
        startupResources = lib.mkOption {
          type = lib.types.listOf (lib.types.attrsOf (pkgs.formats.json {}).type);
          default = [];
          description = "Public Teleport resources applied at startup. Do not include secrets.";
        };
        dataVolume = lib.mkOption {
          type = lib.types.str;
          description = "Docker volume name or host directory for persistent Teleport state.";
        };
      };

      config = lib.mkMerge ([ {
        assertions = [
          {
            assertion = config.virtualisation.docker.enable && config.virtualisation.oci-containers.backend == "docker";
            message = "The Teleport control plane requires Docker and the Docker OCI backend.";
          }
          {
            assertion = !traefikIntegrationEnabled || (
              builtins.elem "proxy" containers.teleport-control-plane.networks
              && builtins.elem "proxy" containers.traefik.networks
            );
            message = "Teleport's Traefik integration requires both containers on the proxy network, or set deployment.teleport-control-plane.overrideTraefikIntegration = true.";
          }
        ];
        virtualisation.oci-containers.containers.teleport-control-plane = {
          image = "public.ecr.aws/gravitational/teleport-distroless:18.11.10";
          entrypoint = "/usr/local/bin/teleport";
          volumes = [ "${configFile}:/etc/teleport/teleport.yaml:ro" "${cfg.dataVolume}:/var/lib/teleport" ]
            ++ lib.optional applyStartupResources "${startupResources}:${containerResources}:ro";
          cmd = [ "start" "--config=/etc/teleport/teleport.yaml" ]
            ++ lib.optional applyStartupResources "--apply-on-startup=${containerResources}";

          labels = lib.mkIf traefikIntegrationEnabled {
            "traefik.enable" = "true";
            "traefik.docker.network" = "proxy";
            "traefik.http.routers.teleport-control-plane.rule" = "Host(`${cfg.domain}`)";
            "traefik.http.routers.teleport-control-plane.entrypoints" = "websecure";
            "traefik.http.routers.teleport-control-plane.service" = "teleport-control-plane";
            "traefik.http.routers.teleport-control-plane.tls.certresolver" = "letsencrypt";
            "traefik.http.services.teleport-control-plane.loadbalancer.server.port" = "3080";
            "traefik.http.services.teleport-control-plane.loadbalancer.server.scheme" = "https";
            "traefik.http.services.teleport-control-plane.loadbalancer.serverstransport" = "teleport-control-plane@file";
          };
        };
      } ] ++ lib.optionals hasTraefikTransport [ (lib.mkIf traefikIntegrationEnabled {
        deployment.traefik.dynamicConfig.http.serversTransports.teleport-control-plane = {
          serverName = cfg.domain;
          rootCAs = [ trustFile ];
          disableHTTP2 = true;
        };

        virtualisation.oci-containers.containers = {
          teleport-control-plane.volumes = [ "${originDirectory}:/etc/teleport/origin:ro" ];
          traefik.volumes = [ "${originDirectory}/cert.pem:${trustFile}:ro" ];
        };

        systemd.services = {
          ${containers.teleport-control-plane.serviceName} = originDependency;
          ${containers.traefik.serviceName} = originDependency;
          teleport-origin-tls = {
            description = "Generate the private Teleport origin certificate";
            path = [ pkgs.openssl ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              RuntimeDirectory = "teleport-origin-tls";
              RuntimeDirectoryMode = "0700";
              UMask = "0077";
            };
            # Both consumers start after this unit; Traefik pins the public cert only.
            script = ''
              openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
                -days 3650 -subj ${lib.escapeShellArg "/CN=${cfg.domain}"} \
                -addext ${lib.escapeShellArg "subjectAltName=DNS:${cfg.domain}"} \
                -addext basicConstraints=critical,CA:FALSE -addext extendedKeyUsage=serverAuth \
                -keyout ${originDirectory}/key.pem -out ${originDirectory}/cert.pem
              chmod 0444 ${originDirectory}/cert.pem
            '';
          };
        };
      }) ]);
    };
}
