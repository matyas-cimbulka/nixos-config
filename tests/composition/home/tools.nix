{ config, lib, compositionHelpers, ... }:
let
  inherit (compositionHelpers) mkHome check;
  modules = config.flake.modules.homeManager;
  names = [ "bat" "btop" "eza" "fd" "fzf" "jq" "ncdu" "nom" "rg" "zoxide" ];
  standalone = lib.genAttrs names (name: mkHome [ modules."matyas-cli-${name}" ] {});
  shared = mkHome [ modules.matyas-server ] {};
  hasPackage = configuration: name: lib.any (package: lib.getName package == name) configuration.config.home.packages;
in
{
  flake.lib.compositionTests.home-tools = {
    tools-work-without-user-profile = check "CLI tools should be independently selectable without Fish or personal profile imports."
      (lib.all (name: !standalone.${name}.config.programs.fish.enable) names
        && standalone.btop.config.programs.btop.enable
        && standalone.fd.config.programs.fd.enable
        && standalone.jq.config.programs.jq.enable
        && standalone.rg.config.programs.ripgrep.enable
        && standalone.bat.config.programs.bat.enable
        && standalone.eza.config.programs.eza.enable
        && standalone.fzf.config.programs.fzf.enable
        && standalone.zoxide.config.programs.zoxide.enable);
    package-only-tools-are-installed = check "Standalone ncdu and nix-output-monitor should contribute their packages."
      (hasPackage standalone.ncdu "ncdu" && hasPackage standalone.nom "nix-output-monitor");
    shared-profile-selects-debugging-tools = check "The shared profile should include resource, disk, search, JSON, and Nix-output debugging tools."
      (shared.config.programs.btop.enable && shared.config.programs.fd.enable
        && shared.config.programs.jq.enable && shared.config.programs.ripgrep.enable
        && hasPackage shared "ncdu" && hasPackage shared "nix-output-monitor");
    fish-integrations-compose = check "Shared Fish should receive the selected CLI integrations."
      (shared.config.programs.fish.enable && shared.config.programs.eza.enableFishIntegration
        && shared.config.programs.fzf.enableFishIntegration && shared.config.programs.zoxide.enableFishIntegration);
  };
}
