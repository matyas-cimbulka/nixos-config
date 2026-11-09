{
  flake.modules.homeManager.matyas-cli-jj = {
    programs.jujutsu = {
      enable = true;

      settings.ui.default-command = "log";
    };
  };
}
