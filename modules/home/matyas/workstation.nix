{ inputs, config, ... }:
let homeModules = config.flake.modules.homeManager;
in
{
  flake.homeConfigurations.matyas-workstation = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };

    modules = [
      config.flake.modules.homeManager.matyas-workstation
    ];
  };

  flake.modules.homeManager.matyas-workstation = { config, ... }:
  let
    identity = { name = "Matyas Cimbulka"; email = "matyas.cimbulka@gmail.com"; };
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHuanqwyg+nSluVQKYa5CsEmxjJLW5JKQosV2D7h1rKP";
    signingKey = "${config.home.homeDirectory}/.ssh/signing.pub";
  in {
    imports = [
      homeModules.matyas-base
      homeModules.matyas-desktop-hyprland
      homeModules.matyas-desktop-ghostty
      homeModules.matyas-desktop-noctalia
      homeModules.matyas-desktop-chrome
      homeModules.matyas-desktop-onepassword
      homeModules.matyas-desktop-vscode
      homeModules.matyas-desktop-nautilus
    ];

    deployment = {
      git.development.enable = true;
      jujutsu.development = { enable = true; signing.key = signingKey; };
    };
    home.file.".ssh/signing.pub".text = "${publicKey}\n";
    programs = {
      git = {
        settings.user = identity;
        signing = {
          key = signingKey;
          allowedSigners = "${identity.email} namespaces=\"git\" ${publicKey}\n";
        };
      };
      jujutsu.settings = {
        user = identity;
        signing.backends.ssh.allowed-signers = "${config.xdg.configHome}/git/allowed_signers";
      };
    };
  };
}
