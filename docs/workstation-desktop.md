# Minimal workstation desktop

The workstation profiles select a minimal Hyprland and Ghostty session. Noctalia,
the graphical greeter, audio configuration, and desktop keyring integration will
follow separately. Installation remains deferred.

The NixOS `hyprland` feature enables the system compositor, desktop portal, and
UWSM integration through the native NixOS module. The workstation profile selects
it explicitly. The Matyas workstation home independently selects its Hyprland
configuration and Ghostty.

Shared Home Manager delivery coordinates each enabled Hyprland home with the
enabled NixOS compositor: NixOS owns compositor and portal installation, UWSM
owns the session, and `~/.config/uwsm/env` loads Home Manager session variables.
Without UWSM, Home Manager retains session management. Standalone Home Manager
installs its own compositor and portal and manages its own session.

The generated configuration uses Lua for the pinned Hyprland version. Connected
monitors use their preferred mode with automatic positioning and scale.

| Binding | Action |
| --- | --- |
| Super + Return | Open Ghostty |
| Super + Q | Close the focused window |
| Super + Shift + E | Log out of the Hyprland session |

On the NixOS workstation, terminal launch uses `uwsm app` and logout uses
`uwsm stop`. The standalone configuration uses normal compositor dispatchers.
Ghostty's appearance is managed by the Matyas Ghostty Home Manager module, which
also installs Fira Code Nerd Font for the configured font family.

Composition tests cover profile selection, package coherence including overrides,
session ownership, multiple Home Manager users, and the generated configuration.
Builds and `Hyprland --verify-config` validate artifacts and configuration syntax;
they do not establish graphical startup, physical monitor behavior, or live Home
Manager activation. Those remain separate boot-time acceptance checks.
