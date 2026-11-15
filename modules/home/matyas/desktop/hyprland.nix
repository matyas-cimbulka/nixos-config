{
  flake.modules.homeManager.matyas-desktop-hyprland = { config, lib, ... }:
  let
    terminal = if config.programs.ghostty.package == null then "ghostty"
      else lib.getExe config.programs.ghostty.package;
    terminalCommand = if config.wayland.windowManager.hyprland.systemd.enable
      then terminal else "uwsm app -- ${terminal}";
    exec = command: lib.generators.mkLuaInline "hl.dsp.exec_cmd(${lib.generators.toLua {} command})";
    logout = if config.wayland.windowManager.hyprland.systemd.enable
      then lib.generators.mkLuaInline "hl.dsp.exit()" else exec "uwsm stop";
    workspaces = lib.range 1 5;
  in
  {
    wayland.windowManager.hyprland = {
      enable = true;
      configType = "lua";
      settings = {
        monitor = {
          output = "";
          mode = "preferred";
          position = "auto";
          scale = "auto";
        };
        bind = [
          { _args = [ "SUPER + RETURN" (exec terminalCommand) ]; }
          { _args = [ "SUPER + Q" (lib.generators.mkLuaInline "hl.dsp.window.close()") ]; }
          { _args = [ "SUPER + SHIFT + E" logout ]; }
        ] ++ lib.concatMap (number:
          let workspace = toString number;
          in [
            { _args = [ "SUPER + ${workspace}" (lib.generators.mkLuaInline "hl.dsp.focus({ workspace = ${workspace} })") ]; }
            { _args = [ "SUPER + SHIFT + ${workspace}" (lib.generators.mkLuaInline "hl.dsp.window.move({ workspace = ${workspace} })") ]; }
          ]) workspaces;
      };
      extraConfig = lib.concatMapStringsSep "\n"
        (number: ''hl.workspace_rule({ workspace = "${toString number}", persistent = true })'') workspaces;
    };
  };
}
