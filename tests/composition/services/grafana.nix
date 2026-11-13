{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkSystem extend check ports failsEvaluation failedAssertion;
  modules = config.flake.modules.nixos;
  settings.deployment.grafana = {
    interfaces = [ "web0" ]; domain = "grafana.example.invalid";
    secretKeyFile = "/run/test-secrets/grafana-key"; overrideOAuthIntegration = true;
  };
  active = mkSystem [ modules.grafana ] settings;
  disabled = mkSystem [ modules.grafana ] { services.grafana.enable = false; };
  missingInterface = mkSystem [ modules.grafana ] {
    deployment.grafana = { domain = "grafana.example.invalid"; secretKeyFile = "/run/test-secrets/key"; overrideOAuthIntegration = true; };
  };
  missingDomain = mkSystem [ modules.grafana ] { deployment.grafana.interfaces = [ "web0" ]; };
  missingKey = mkSystem [ modules.grafana ] {
    deployment.grafana = { interfaces = [ "web0" ]; domain = "grafana.example.invalid"; overrideOAuthIntegration = true; };
  };
  backends = extend active {
    services = { prometheus.enable = true; loki.enable = true; tempo.enable = true; };
  };
  customBackends = extend backends {
    services.prometheus = { listenAddress = "::"; port = 19090; };
    services.loki.configuration.server = { http_listen_address = "0.0.0.0"; http_listen_port = 13100; };
    services.tempo.settings.server = { http_listen_address = "10.0.0.7"; http_listen_port = 13200; };
  };
  optOut = extend backends {
    deployment.grafana = { overridePrometheusIntegration = true; overrideLokiIntegration = true; overrideTempoIntegration = true; };
  };
  noProvision = extend backends { services.grafana.provision.enable = false; };
  oauth = extend active {
    deployment.grafana = { overrideOAuthIntegration = lib.mkForce false; oauthClientSecretFile = "/run/test-secrets/oauth"; };
    services.grafana.settings."auth.generic_oauth" = {
      client_id = "test-client"; auth_url = "https://id.example.invalid/authorize";
      token_url = "https://id.example.invalid/token"; api_url = "https://id.example.invalid/userinfo";
      jwk_set_url = "https://id.example.invalid/jwks";
    };
  };
  missingOauth = extend active {
    deployment.grafana = { overrideOAuthIntegration = lib.mkForce false; oauthClientSecretFile = "/run/test-secrets/oauth"; };
  };
  missingOauthSecret = extend active { deployment.grafana.overrideOAuthIntegration = lib.mkForce false; };
  sources = configuration: configuration.config.services.grafana.provision.datasources.settings.datasources or [];
  urls = configuration: map (source: source.url) (sources configuration);
in
{
  flake.lib.compositionTests.grafana = {
    enables-service = check "The Grafana feature should enable Grafana." active.config.services.grafana.enable;
    uses-domain-and-runtime-key = check "Grafana should consume deployment domain and runtime secret references."
      (active.config.services.grafana.settings.server.root_url == "https://grafana.example.invalid"
        && active.config.services.grafana.settings.security.secret_key == "$__file{/run/test-secrets/grafana-key}");
    interface-specific-port = check "Grafana should open HTTP only on deployment interfaces."
      (ports active "web0" == [ 3000 ] && active.config.networking.firewall.allowedTCPPorts == []);
    no-backends-means-no-data-sources = check "Grafana alone should not provision unavailable local data sources."
      (sources active == []);
    native-backends-activate-data-sources = check "Grafana should provision all enabled native local backends."
      (map (source: source.uid) (sources backends) == [ "prometheus" "loki" "tempo" ]);
    data-source-addresses-follow-backends = check "Grafana should normalize wildcard/IPv6 addresses and follow backend ports."
      (urls customBackends == [ "http://[::1]:19090" "http://127.0.0.1:13100" "http://10.0.0.7:13200" ]);
    integration-opt-outs-remove-data-sources = check "Grafana backend opt-outs should remove provisioned data sources."
      (sources optOut == [] && optOut.config.services.grafana.provision.datasources.settings.prune);
    disabling-provisioning-removes-data-sources = check "Grafana provisioning disable should remove the module's data sources."
      (sources noProvision == []);
    oauth-uses-runtime-secret = check "Active Grafana OAuth should use its supplied runtime secret and enable PKCE."
      (oauth.config.services.grafana.settings."auth.generic_oauth".client_secret == "$__file{/run/test-secrets/oauth}"
        && oauth.config.services.grafana.settings."auth.generic_oauth".use_pkce);
    oauth-opt-out-needs-no-secret = check "Grafana OAuth opt-out should not require a client secret or enable Generic OAuth."
      (!(active.config.services.grafana.settings."auth.generic_oauth".enabled or false));
    missing-oauth-settings-declare-failures = check "Grafana should assert all missing active OAuth deployment settings."
      (lib.all (key: failedAssertion missingOauth
        "Grafana OAuth requires services.grafana.settings.auth.generic_oauth.${key} supplied by the deployment.")
        [ "client_id" "auth_url" "token_url" "api_url" "jwk_set_url" ]);
    missing-oauth-secret-is-rejected = check "Active Grafana OAuth should require its runtime client-secret path."
      (failsEvaluation missingOauthSecret.config.services.grafana.settings."auth.generic_oauth".client_secret);
    missing-domain-is-rejected = check "Active Grafana should require its deployment domain."
      (failsEvaluation missingDomain.config.services.grafana.settings.server.domain);
    missing-signing-key-is-rejected = check "Active Grafana should require its runtime signing-key path."
      (failsEvaluation missingKey.config.services.grafana.settings.security.secret_key);
    missing-interface-is-rejected = check "Active Grafana should require explicitly supplied interfaces."
      (failsEvaluation missingInterface.config.networking.firewall.interfaces);
    disable-removes-support = check "Disabled Grafana should need no deployment values and leave no data sources or firewall contribution."
      (!(disabled.config.systemd.services ? grafana) && sources disabled == []
        && disabled.config.networking.firewall.interfaces == {});
  };
}
