{ config, deploymentHelpers, lib, ... }:
let
  inherit (deploymentHelpers) host guest check credentialWiring sameMembers internalHost targets job tcpPorts bridgeAddress commandValue;
  thoth = guest "thoth";
  anderson = guest "anderson";
  behemoth = guest "behemoth";
  lan = thoth.deployment.microvm.interfaceName;
  containers = behemoth.virtualisation.oci-containers.containers;
  sources = thoth.services.grafana.provision.datasources.settings.datasources;
  source = uid: lib.findFirst (entry: entry.uid == uid) (throw "Missing Grafana ${uid} data source.") sources;
  remoteMachines = [ host anderson behemoth ];
  remoteAddresses = [ bridgeAddress (internalHost anderson) (internalHost behemoth) ];
  exporterTargets = port: lib.imap0 (index: machine: "${builtins.elemAt remoteAddresses index}:${toString (port machine)}") remoteMachines;
  traefikMetricsPort = lib.removePrefix ":" (commandValue "--entrypoints.traefik.address=" containers.traefik.cmd);
  lokiEndpoint = "http://${internalHost thoth}:${toString thoth.services.loki.configuration.server.http_listen_port}/loki/api/v1/push";
  tempoEndpoint = "${internalHost thoth}:${toString thoth.deployment.tempo.otlpPort}";
  oauth = thoth.services.grafana.settings."auth.generic_oauth";
  disabledHost = (config.flake.nixosConfigurations.tycho.extendModules {
    modules = [{ deployment.enableGrafanaMcp = lib.mkForce false; }];
  }).config;
  disabledThoth = disabledHost.microvm.vms.thoth.config.config;
  mcpResources = behemoth.deployment.teleport-control-plane.startupResources;
  resource = kind: name: lib.findFirst (r: r.kind == kind && r.metadata.name == name) {} mcpResources;
  idUrl = "https://${behemoth.deployment.pocket-id.domain}";
in
{
  flake.lib.deploymentTests.thoth = {
    grafana-mcp-credential-wiring = credentialWiring {
      vm = "thoth"; service = "grafana-mcp"; name = "grafana-mcp-token";
      source = host.sops.secrets.grafana-mcp-token.path;
      consumedPaths = [ thoth.systemd.services.grafana-mcp.environment.GRAFANA_SERVICE_ACCOUNT_TOKEN_FILE ];
    };
    grafana-mcp-opt-out = check "Disabling Grafana MCP should remove its service, credential, and Teleport app."
      (!(disabledThoth.systemd.services ? grafana-mcp) && !(disabledHost.sops.secrets ? grafana-mcp-token)
        && !(disabledThoth.services.teleport.settings ? app_service));
    grafana-mcp-teleport-registration = check "Thoth should register the loopback MCP app using its existing node identity and an expanded join token."
      (thoth.services.teleport.settings.ssh_service.enabled
        && thoth.services.teleport.settings.app_service.enabled
        && thoth.services.teleport.settings.app_service.apps == [{
          name = "grafana-mcp";
          uri = "mcp+http://127.0.0.1:8000/mcp";
          labels.access = "grafana-mcp";
        }]
        && (resource "token" "thoth-node").spec.roles == [ "Node" "App" ]);
    grafana-mcp-bot-roles = check "Each bot should have only its Grafana MCP role, and only the repo role should allow dashboard writes."
      (let
        repo = (resource "role" "grafana-mcp-repo").spec.allow;
        debug = (resource "role" "grafana-mcp-debug").spec.allow;
      in
        (resource "bot" "grafana-mcp-repo").spec.roles == [ "grafana-mcp-repo" ]
        && (resource "bot" "grafana-mcp-debug").spec.roles == [ "grafana-mcp-debug" ]
        && repo.app_labels == { access = "grafana-mcp"; } && debug.app_labels == repo.app_labels
        && debug.mcp.tools == [
          "search_dashboards" "get_dashboard_by_uid" "get_dashboard_panel_queries"
          "get_dashboard_property" "get_dashboard_summary" "list_datasources" "get_datasource"
          "query_prometheus" "list_prometheus_metric_metadata" "list_prometheus_metric_names"
          "list_prometheus_label_names" "list_prometheus_label_values"
          "query_loki_logs" "list_loki_label_names" "list_loki_label_values"
        ]
        && repo.mcp.tools == debug.mcp.tools ++ [ "update_dashboard" ]);
    grafana-signing-key-wiring = credentialWiring {
      vm = "thoth"; service = "grafana"; name = "grafana-secret-key";
      source = host.sops.secrets.grafana-secret-key.path;
      consumedPaths = [ thoth.services.grafana.settings.security.secret_key ];
      formatPath = path: "$__file{${path}}";
    };
    grafana-oauth-secret-wiring = credentialWiring {
      vm = "thoth"; service = "grafana"; name = "grafana-oidc-client-secret";
      source = host.sops.secrets.grafana-oidc-client-secret.path;
      consumedPaths = [ oauth.client_secret ];
      formatPath = path: "$__file{${path}}";
    };
    grafana-local-data-sources-follow-backends = check "Grafana data sources must connect to Thoth's enabled local backends and effective ports."
      (thoth.services.prometheus.enable && thoth.services.loki.enable && thoth.services.tempo.enable
        && sameMembers (map (entry: entry.uid) sources) [ "prometheus" "loki" "tempo" ]
        && (source "prometheus").url == "http://127.0.0.1:${toString thoth.services.prometheus.port}"
        && (source "loki").url == "http://127.0.0.1:${toString thoth.services.loki.configuration.server.http_listen_port}"
        && (source "tempo").url == "http://127.0.0.1:${toString thoth.services.tempo.settings.server.http_listen_port}");
    grafana-scrape-interval-follows-prometheus = check "Grafana's default Prometheus data source must use the deployed scrape interval."
      ((source "prometheus").isDefault
        && (source "prometheus").jsonData.timeInterval == thoth.services.prometheus.globalConfig.scrape_interval);
    grafana-oauth-follows-pocket-id = check "Grafana OAuth endpoints must point to the deployed Pocket ID domain."
      (oauth.enabled && oauth.client_id != ""
        && oauth.auth_url == "${idUrl}/authorize"
        && oauth.token_url == "${idUrl}/api/oidc/token"
        && oauth.api_url == "${idUrl}/api/oidc/userinfo"
        && oauth.jwk_set_url == "${idUrl}/.well-known/jwks.json");
    grafana-oauth-maps-dedicated-org-admin-group = check "Pocket ID grafan-admin must grant organization Admin, while admin remains Editor and server admin stays disabled."
      (oauth.role_attribute_path == "contains(groups || `[]`, 'grafan-admin') && 'Admin' || contains(groups || `[]`, 'admin') && 'Editor' || 'Viewer'"
        && !oauth.allow_assign_grafana_admin && !oauth.skip_org_role_sync);
    resolver-keeps-bridge-as-default-dns-route = check "Thoth must allow bridge DNS to resolve the public Pocket ID hostname used by OAuth."
      thoth.systemd.network.networks.lan.networkConfig.DNSDefaultRoute;
    system-scrape-targets-follow-exporters = check "Thoth must scrape local Alloy and each deployed remote Alloy using its effective port."
      (lib.all (machine: machine.services.alloy.enable) (remoteMachines ++ [ thoth ])
        && sameMembers (targets thoth "system")
          ([ "127.0.0.1:${toString thoth.deployment.alloy.httpPort}" ] ++ exporterTargets (machine: machine.deployment.alloy.httpPort))
        && (job thoth "system").metrics_path == "/api/v0/component/prometheus.exporter.unix.system/metrics");
    system-scrape-targets-have-machine-labels = check "Each system scrape address must carry its machine name as a static target label."
      (let
        configs = (job thoth "system").static_configs;
        expected = lib.zipLists (remoteMachines ++ [ thoth ])
          (exporterTargets (machine: machine.deployment.alloy.httpPort) ++ [ "127.0.0.1:${toString thoth.deployment.alloy.httpPort}" ]);
      in lib.all ({ fst, snd }: lib.any (entry:
        builtins.elem snd entry.targets && (entry.labels.machine or null) == fst.networking.hostName
      ) configs) expected);
    tailscale-scrape-targets-follow-exporters = check "Thoth must scrape each deployed Tailscale metrics listener using its effective port."
      (lib.all (machine: machine.services.tailscale.enable && !machine.deployment.tailscale.overrideMetricsIntegration) remoteMachines
        && sameMembers (targets thoth "tailscale") (exporterTargets (machine: machine.deployment.tailscale.metricsPort))
        && (job thoth "tailscale").metrics_path == "/metrics");
    pocket-id-scrape-follows-exporter = check "Pocket ID scraping must target Behemoth's active Prometheus listener."
      (containers.pocket-id.environment.OTEL_METRICS_EXPORTER == "prometheus"
        && targets thoth "pocket-id" == [ "${internalHost behemoth}:${toString behemoth.deployment.pocket-id.metricsPort}" ]
        && (job thoth "pocket-id").metrics_path == "/metrics");
    cadvisor-scrape-follows-exporter = check "Docker scraping must target Behemoth's enabled cAdvisor port."
      (behemoth.services.cadvisor.enable
        && targets thoth "docker" == [ "${internalHost behemoth}:${toString behemoth.services.cadvisor.port}" ]);
    traefik-scrape-follows-exporter = check "Traefik scraping must follow the deployed metrics entrypoint and internal exposure."
      (targets thoth "traefik" == [ "${internalHost behemoth}:${traefikMetricsPort}" ]
        && commandValue "--metrics.prometheus.entrypoint=" containers.traefik.cmd == "traefik"
        && builtins.elem (lib.toInt traefikMetricsPort) behemoth.deployment.traefik.portsByInterface.${behemoth.deployment.microvm.interfaceName});
    remote-exporters-have-internal-openings = check "The scraped exporters must contribute access on the host bridge or guest LAN."
      (lib.all (machine: let interface = if machine.networking.hostName == host.networking.hostName
          then deploymentHelpers.bridgeName else machine.deployment.microvm.interfaceName; in
        builtins.elem machine.deployment.alloy.httpPort (tcpPorts machine interface)
        && builtins.elem machine.deployment.tailscale.metricsPort (tcpPorts machine interface)) remoteMachines
        && builtins.elem behemoth.deployment.pocket-id.metricsPort (tcpPorts behemoth behemoth.deployment.microvm.interfaceName)
        && builtins.elem behemoth.services.cadvisor.port (tcpPorts behemoth behemoth.deployment.microvm.interfaceName));
    log-forwarding-follows-loki = check "All deployed Alloy journal pipelines must forward to Thoth's actual Loki endpoint."
      (lib.all (machine: machine.deployment.alloy.lokiEndpoint == lokiEndpoint
        && lib.hasInfix (builtins.toJSON lokiEndpoint) machine.environment.etc."alloy/logs.alloy".text) (remoteMachines ++ [ thoth ]));
    trace-forwarding-follows-tempo = check "Behemoth's Alloy trace pipeline must forward to Thoth's actual Tempo receiver."
      (behemoth.deployment.alloy.tempoEndpoint == tempoEndpoint
        && lib.hasInfix (builtins.toJSON tempoEndpoint) behemoth.environment.etc."alloy/traces.alloy".text
        && builtins.elem thoth.deployment.tempo.otlpPort (tcpPorts thoth lan));
    monitoring-apis-stay-internal = check "Thoth must explicitly expose its monitoring APIs only on the internal guest interface."
      (thoth.deployment.grafana.interfaces == [ lan ] && thoth.deployment.prometheus.interfaces == [ lan ]
        && thoth.deployment.loki.interfaces == [ lan ] && thoth.deployment.tempo.apiInterfaces == [ lan ]
        && thoth.deployment.tempo.otlpInterfaces == [ lan ]);
  };
}
