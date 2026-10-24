{ config, ... }:
{
  flake.modules.homeManager.matyas-cli-git = {
    programs.git = {
      enable = true;

      ignores = [
        ".claude"
      ];

      signing = {
        format = "ssh";
        key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHuanqwyg+nSluVQKYa5CsEmxjJLW5JKQosV2D7h1rKP";
      };

      settings = {
        user = {
          name = "Matyas Cimbulka";
          email = "matyas.cimbulka@gmail.com";
        };

        init.defaultBranch = "main";
        pull.rebase = true;
        push.autoSetupRemote = true;
        commit.gpgSign = true;
        core.editor = "nvim";
        rerere.enabled = true;

        url."git@github.com:".insteadOf = "https://github.com/";
      };
    };
  };

  flake.modules.homeManager.matyas-base.imports = [
    config.flake.modules.homeManager.matyas-cli-git
  ];
}
