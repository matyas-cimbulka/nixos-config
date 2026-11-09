{
  flake.modules.homeManager.matyas-cli-git = {
    programs.git = {
      enable = true;

      ignores = [ ".claude" ];

      settings = {
        init.defaultBranch = "main";
        pull.rebase = true;
        push.autoSetupRemote = true;
        rerere.enabled = true;
      };
    };
  };
}
