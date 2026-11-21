{
  flake.modules.homeManager.matyas-desktop-chrome = { config, lib, ... }:
  let enabled = config.programs.google-chrome.enable;
  in {
    programs.google-chrome.enable = lib.mkDefault true;
    xdg.mimeApps = lib.mkIf enabled {
      enable = true;
      defaultApplications = lib.genAttrs [ "text/html" "x-scheme-handler/http" "x-scheme-handler/https" ]
        (_: lib.mkDefault [ "google-chrome.desktop" ]);
    };
  };
}
