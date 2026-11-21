{ lib, fetchFromGitHub, hyprlandPlugins, hyprland, lua5_4 }:
hyprlandPlugins.mkHyprlandPlugin {
  inherit hyprland;
  pluginName = "scrolloverview";
  version = "0-unstable-07a944e";
  src = fetchFromGitHub {
    owner = "yayuuu";
    repo = "hyprland-scroll-overview";
    # Upstream's compatibility pin for Hyprland 0.56.2. Revalidate on upgrades.
    rev = "07a944e4d16f11d2d9be6ce10bea74a6f1e5f2ae";
    hash = "sha256-M4NbHbRn/YGDGP54ts/WGxPjQhZMcGy1cIqQ5D89C3E=";
  };
  buildInputs = [ lua5_4 ];
  dontUseCmakeConfigure = true;
  env.SCROLLOVERVIEW_BUILD_VERSION = "07a944e";
  installPhase = ''
    runHook preInstall
    install -Dm755 scrolloverview.so $out/lib/libscrolloverview.so
    runHook postInstall
  '';
  passthru = { inherit hyprland; };
  meta = {
    description = "Native scrolling workspace overview for Hyprland";
    homepage = "https://github.com/yayuuu/hyprland-scroll-overview";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
  };
}
