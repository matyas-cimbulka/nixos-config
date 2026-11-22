{ config, deploymentHelpers, lib, ... }:
let
  inherit (deploymentHelpers) host guest check credentialWiring sameMembers tcpPorts internalHost commandValue;
  behemoth = guest "behemoth";
  thoth = guest "thoth";
  containers = behemoth.virtualisation.oci-containers.containers;
  lan = behemoth.deployment.microvm.interfaceName;
  proxy = behemoth.deployment.docker-proxy;
  traceEndpoint = "http://${proxy.gateway}:4318/v1/traces";
  grafana = behemoth.deployment.traefik.dynamicConfig.http;
  fixtureKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILRrD9u9iWKpWBbFj4gL+KgQF7jCKfVkLGXc3N2QvIAR";
  enrollmentHost = (config.flake.nixosConfigurations.tycho.extendModules {
    modules = [{ deployment.teleportEnrollmentPublicKeys.behemoth = lib.mkForce fixtureKey; }];
  }).config;
  enrollment = import ./helpers.nix { host = enrollmentHost; inherit lib; };
  enrolledBehemoth = enrollment.guest "behemoth";
  withoutEnrollment = overrides: let
    host = (config.flake.nixosConfigurations.tycho.extendModules { modules = [ overrides ]; }).config;
    guest = (import ./helpers.nix { inherit host lib; }).guest "behemoth";
    controlPlane = guest.virtualisation.oci-containers.containers.teleport-control-plane;
  in !guest.services.teleport.enable
    && !(host.sops.secrets ? behemoth-teleport-enrollment-key)
    && !(guest.microvm.credentialFiles ? teleport-join-key)
    && !(lib.any (lib.hasPrefix "teleport-join-key:") host.systemd.services."microvm@behemoth".serviceConfig.LoadCredential)
    && controlPlane.autoStart
    && builtins.elem "--apply-on-startup=/etc/teleport/enrollment.json" controlPlane.cmd
    && lib.all (resource: resource.kind != "token" || resource.metadata.name != "behemoth-node")
      guest.deployment.teleport-control-plane.startupResources;
  startupResources = let
    teleport = enrolledBehemoth.virtualisation.oci-containers.containers.teleport-control-plane;
    mount = lib.findFirst (lib.hasSuffix ":/etc/teleport/enrollment.json:ro") (throw "Missing startup manifest mount.") teleport.volumes;
    manifest = builtins.readFile (lib.removeSuffix ":/etc/teleport/enrollment.json:ro" mount);
  in map builtins.fromJSON (lib.splitString "\n---\n" (lib.removePrefix "---\n" manifest));
in
{
  flake.lib.deploymentTests.behemoth = {
    traefik-credential-wiring = credentialWiring {
      vm = "behemoth"; service = containers.traefik.serviceName; name = "cloudflare-dns.env";
      source = host.sops.templates."cloudflare-dns.env".path;
      consumedPaths = containers.traefik.environmentFiles;
    };
    pocket-id-credential-wiring = credentialWiring {
      vm = "behemoth"; service = containers.pocket-id.serviceName; name = "pocket-id.env";
      source = host.sops.templates."pocket-id.env".path;
      consumedPaths = containers.pocket-id.environmentFiles;
    };
    tailscale-credential-wiring = credentialWiring {
      vm = "behemoth"; service = "tailscaled-autoconnect"; name = "tailscale-vm-oauth";
      source = host.sops.secrets.tailscale-vm-oauth.path;
      consumedPaths = [ behemoth.services.tailscale.authKeyFile ];
    };
    environment-templates-use-intended-secrets = check "Behemoth environment templates must reference their intended SOPS secrets."
      (lib.hasInfix "CF_DNS_API_TOKEN=${host.sops.placeholder.cloudflare-dns-api-token}" host.sops.templates."cloudflare-dns.env".content
        && lib.hasInfix "ENCRYPTION_KEY=${host.sops.placeholder.pocket-id-encryption-key}" host.sops.templates."pocket-id.env".content
        && lib.hasInfix "SMTP_PASSWORD=${host.sops.placeholder.pocket-id-smtp-password}" host.sops.templates."pocket-id.env".content
        && host.sops.templates."cloudflare-dns.env".mode == "0400"
        && host.sops.templates."pocket-id.env".mode == "0400");
    traefik-exposure-is-explicit = check "Behemoth must explicitly permit 80/443/8080 on LAN and Tailscale for the current debugging policy."
      (sameMembers (builtins.attrNames behemoth.deployment.traefik.portsByInterface) [ lan "tailscale0" ]
        && sameMembers behemoth.deployment.traefik.portsByInterface.${lan} [ 80 443 8080 ]
        && sameMembers behemoth.deployment.traefik.portsByInterface.tailscale0 [ 80 443 8080 ]
        && lib.all (port: builtins.elem port (tcpPorts behemoth lan) && builtins.elem port (tcpPorts behemoth "tailscale0")) [ 80 443 8080 ]);
    traefik-publication-matches-exposure = check "Traefik must publish exactly the deployment-approved host ports."
      (sameMembers containers.traefik.ports [ "80:80" "443:443" "8080:8080" ]
        && behemoth.networking.nftables.tables ? traefik-exposure
        && lib.hasInfix "priority -110" behemoth.networking.nftables.tables.traefik-exposure.content);
    pocket-id-routing-uses-proxy-network = check "Pocket ID and Traefik must share the proxy network and publish the intended ID route."
      (builtins.elem "proxy" containers.pocket-id.networks && builtins.elem "proxy" containers.traefik.networks
        && containers.pocket-id.labels."traefik.http.routers.pocket-id.rule" == "Host(`${behemoth.deployment.pocket-id.domain}`)"
        && containers.pocket-id.labels."traefik.http.services.pocket-id.loadbalancer.server.port" == "1411"
        && containers.pocket-id.labels."traefik.docker.network" == "proxy"
        && commandValue "--providers.docker.network=" containers.traefik.cmd == "proxy"
        && containers.pocket-id.environment.TRUST_PROXY == proxy.subnet);
    native-teleport-enrollment = check "Behemoth must enroll its native node over the HTTPS proxy and persist identity outside the container."
      (let
        behemoth = enrolledBehemoth;
        node = behemoth.services.teleport;
        unit = behemoth.systemd.services.teleport;
      in
        node.enable && node.settings.ssh_service.enabled
        && node.settings.ssh_service.labels == { type = "vm"; }
        && node.settings.teleport.proxy_server == "${behemoth.deployment.teleport-control-plane.domain}:443"
        && node.settings.teleport.join_params == {
          method = "bound_keypair";
          token_name = "behemoth-node";
          bound_keypair.static_key_path = "/run/credentials/teleport.service/teleport-join-key";
        }
        && lib.any (volume: volume.mountPoint == "/var/lib/teleport") behemoth.microvm.volumes
        && builtins.elem "/var/lib/teleport" unit.unitConfig.RequiresMountsFor
        && !(unit.serviceConfig ? ExecStartPost)
        && !(builtins.elem "docker-teleport-control-plane.service" unit.requires));
    teleport-enrollment-key-wiring = enrollment.credentialWiring {
      vm = "behemoth"; service = "teleport"; name = "teleport-join-key";
      source = enrollmentHost.sops.secrets.behemoth-teleport-enrollment-key.path;
      consumedPaths = [ enrolledBehemoth.services.teleport.settings.teleport.join_params.bound_keypair.static_key_path ];
    };
    fw-cfg-credential-names-fit = check "Behemoth's QEMU fw_cfg credential names must fit the 55-byte limit."
      (lib.all (name: builtins.stringLength "opt/io.systemd.credentials/${name}" <= 55)
        (builtins.attrNames enrolledBehemoth.microvm.credentialFiles));
    pending-enrollment-does-not-block-control-plane = check "No enrollment key should be required before the deployment supplies a public key."
      (withoutEnrollment { deployment.teleportEnrollmentPublicKeys.behemoth = lib.mkForce null; });
    disabled-agent-does-not-forward-enrollment-key = check "Disabling the native agent must remove its enrollment wiring, even with a public key configured."
      (withoutEnrollment {
        deployment.teleportEnrollmentPublicKeys.behemoth = lib.mkForce fixtureKey;
        microvm.vms.behemoth.config.services.teleport.enable = lib.mkForce false;
      });
    teleport-declares-matyas-ssh-role = check "Matyas must be allowed to use the Unix login matyas on all enrolled SSH nodes."
      (builtins.elem {
        kind = "role";
        version = "v7";
        metadata.name = "matyas-ssh";
        spec.allow = { logins = [ "matyas" ]; node_labels."*" = "*"; };
      } startupResources);
    teleport-declares-matyas-role-assignments = check "Declare Matyas's existing roles and Grafana MCP dashboard edit access without managing auth secrets."
      (builtins.filter (resource: resource.kind == "user") startupResources == [{
        kind = "user";
        version = "v2";
        metadata.name = "matyas";
        spec.roles = [ "editor" "auditor" "matyas-ssh" "grafana-mcp-repo" ];
      }]);
    teleport-applies-matching-public-key-resource = check "The control plane must apply the same node resource name Behemoth uses, with only the public key."
      (let
        behemoth = enrolledBehemoth;
        teleport = behemoth.virtualisation.oci-containers.containers.teleport-control-plane;
        token = lib.findFirst (resource: resource.kind == "token" && resource.metadata.name == "behemoth-node") (throw "Missing enrollment token in startup manifest.") startupResources;
      in
        token.kind == "token" && token.version == "v2"
        && token.metadata.name == behemoth.services.teleport.settings.teleport.join_params.token_name
        && token.spec.roles == [ "Node" ] && token.spec.join_method == "bound_keypair"
        && token.spec.bound_keypair.onboarding.initial_public_key == fixtureKey
        && !(enrollmentHost.sops.secrets ? behemoth-teleport-enrollment-public-key)
        && token.spec.bound_keypair.recovery.mode == "insecure"
        && builtins.elem "--apply-on-startup=/etc/teleport/enrollment.json" teleport.cmd);
    remaining-machines-enroll = check "Anderson, Thoth and Tycho must have matching startup tokens and durable native identities."
      (let
        endpoint = "${behemoth.deployment.teleport-control-plane.domain}:443";
        tokens = builtins.filter (resource: resource.kind == "token") startupResources;
        nodeMatches = name: type: machine: machine.services.teleport.enable
          && machine.services.teleport.settings.teleport.proxy_server == endpoint
          && machine.services.teleport.settings.ssh_service.labels == { inherit type; }
          && machine.services.teleport.settings.teleport.join_params.token_name == "${name}-node"
          && lib.any (token: token.metadata.name == "${name}-node"
            && token.spec.roles == (if name == "thoth" then [ "Node" "App" ] else [ "Node" ])
            && token.spec.join_method == "bound_keypair"
            && token.spec.bound_keypair.recovery.mode == "insecure"
            && token.spec.bound_keypair.onboarding.initial_public_key == host.deployment.teleportEnrollmentPublicKeys.${name}) tokens;
        vmMatches = name: let vm = guest name; in nodeMatches name "vm" vm
          && lib.any (volume: volume.mountPoint == "/var/lib/teleport") vm.microvm.volumes
          && enrollment.credentialWiring {
            vm = name; service = "teleport"; name = "teleport-join-key";
            source = enrollmentHost.sops.secrets."${name}-teleport-enrollment-key".path;
            consumedPaths = [ (enrollment.guest name).services.teleport.settings.teleport.join_params.bound_keypair.static_key_path ];
          }
          && lib.all (credential: builtins.stringLength "opt/io.systemd.credentials/${credential}" <= 55)
            (builtins.attrNames vm.microvm.credentialFiles);
        tychoKey = host.sops.secrets.tycho-teleport-enrollment-key.path;
      in vmMatches "anderson" && vmMatches "thoth" && nodeMatches "tycho" "server" host
        && builtins.elem "teleport-join-key:${tychoKey}" host.systemd.services.teleport.serviceConfig.LoadCredential
        && host.services.teleport.settings.teleport.join_params.bound_keypair.static_key_path == "/run/credentials/teleport.service/teleport-join-key"
        && builtins.elem "sops-install-secrets.service" host.systemd.services.teleport.after
        && builtins.elem "${behemoth.deployment.teleport-control-plane.domain},${internalHost behemoth}" host.services.dnsmasq.settings.cname);
    teleport-routes-through-traefik = check "Behemoth must serve Teleport through Traefik HTTPS without publishing a Teleport host port."
      (let
        teleport = containers.teleport-control-plane;
        labels = teleport.labels;
      in
        behemoth.deployment.teleport-control-plane.domain == "teleport.cimbulka.net"
        && teleport.ports == [] && builtins.elem "proxy" teleport.networks
        && !(builtins.elem "--insecure-no-tls" teleport.cmd)
        && labels."traefik.http.services.teleport-control-plane.loadbalancer.server.scheme" == "https"
        && labels."traefik.http.services.teleport-control-plane.loadbalancer.serverstransport" == "teleport-control-plane@file"
        && labels."traefik.http.routers.teleport-control-plane.rule" == "Host(`teleport.cimbulka.net`)"
        && labels."traefik.http.routers.teleport-control-plane.entrypoints" == "websecure"
        && labels."traefik.http.routers.teleport-control-plane.tls.certresolver" == "letsencrypt"
        && labels."traefik.http.services.teleport-control-plane.loadbalancer.server.port" == "3080");
    teleport-origin-tls-is-verified = check "Traefik must trust only the Teleport origin certificate for this backend, without access to its private key."
      (let
        teleport = containers.teleport-control-plane;
        cfg = behemoth.deployment.teleport-control-plane;
        transport = behemoth.deployment.traefik.dynamicConfig.http.serversTransports.teleport-control-plane;
        mount = lib.findFirst (lib.hasSuffix ":/etc/teleport/teleport.yaml:ro") (throw "Missing Teleport config mount.") teleport.volumes;
        settings = builtins.fromJSON (builtins.readFile (lib.removeSuffix ":/etc/teleport/teleport.yaml:ro" mount));
        certService = "teleport-origin-tls.service";
      in
        transport.serverName == cfg.domain && !(transport.insecureSkipVerify or false)
        && transport.rootCAs == [ "/etc/traefik/teleport-origin.pem" ]
        && settings.proxy_service.https_keypairs == [{ cert_file = "/etc/teleport/origin/cert.pem"; key_file = "/etc/teleport/origin/key.pem"; }]
        && builtins.elem "/run/teleport-origin-tls:/etc/teleport/origin:ro" teleport.volumes
        && lib.filter (lib.hasPrefix "/run/teleport-origin-tls") containers.traefik.volumes == [ "/run/teleport-origin-tls/cert.pem:/etc/traefik/teleport-origin.pem:ro" ]
        && lib.all (container: let unit = behemoth.systemd.services.${container.serviceName}; in
          builtins.elem certService unit.requires && builtins.elem certService unit.after) [ teleport containers.traefik ]);
    pocket-id-app-is-not-published-on-host = check "Co-located Pocket ID must publish only its separate metrics endpoint."
      (containers.pocket-id.ports == [ "${toString behemoth.deployment.pocket-id.metricsPort}:${toString behemoth.deployment.pocket-id.metricsPort}" ]);
    metrics-and-traces-remain-enabled = check "Behemoth must retain Pocket ID metrics and both application trace senders."
      (containers.pocket-id.environment.OTEL_METRICS_EXPORTER == "prometheus"
        && containers.pocket-id.environment.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT == traceEndpoint
        && commandValue "--tracing.otlp.http.endpoint=" containers.traefik.cmd == traceEndpoint
        && lib.hasInfix "${proxy.gateway}:4318" behemoth.environment.etc."alloy/traces.alloy".text);
    grafana-route-follows-thoth = check "The ingress Grafana route must use Thoth's actual hostname, HTTP port, and public domain."
      (grafana.routers.grafana.rule == "Host(`${thoth.deployment.grafana.domain}`)"
        && grafana.routers.grafana.service == "grafana"
        && grafana.services.grafana.loadBalancer.servers == [ {
          url = "http://${internalHost thoth}:${toString thoth.services.grafana.settings.server.http_port}";
        } ]);
    dns-server-follows-host-bridge = check "Traefik container DNS must use Tycho's bridge DNS service."
      (behemoth.deployment.traefik.dnsServer == deploymentHelpers.bridgeAddress
        && builtins.elem "--dns=${deploymentHelpers.bridgeAddress}" containers.traefik.extraOptions);
  };
}
