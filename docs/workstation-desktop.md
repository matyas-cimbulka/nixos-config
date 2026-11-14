# Minimal workstation desktop

The workstation profiles select a minimal Hyprland and Ghostty session with GNOME
Keyring for local application credentials. Noctalia, the graphical greeter, and
audio configuration will follow separately. Installation remains deferred.

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

## Desktop keyring

The workstation profile explicitly selects the NixOS `gnome-keyring` feature.
The native service supplies a Secret Service provider and optional PAM hooks in
the TTY login stack to unlock and start the login keyring. A future greetd greeter
inherits that stack; it does not need duplicate keyring hooks. The native
`services.gnome.gnome-keyring.enable` option allows opting out. Servers do not
select this feature.

GNOME Keyring stores local desktop application credentials; 1Password remains
the personal vault and installation recovery-key custodian. Keyring files normally
live in `~/.local/share/keyrings`, covered by pella's persistent `/home` subvolume.
Keep the Login keyring as the default collection for Noctalia's future Secret
Service integration.

Automatic unlock requires a password login and a keyring password matching that
login password. TPM disk unlocking does not supply the login password. Changing
the declarative account password hash in `/persist/secrets/matyas-password` does
not run PAM password-change hooks, so an existing keyring password must be updated
separately using its old password. Keep keyring passwords out of Nix configuration.

Composition tests cover password-login hooks, greetd inheritance, explicit opt-out,
and server independence; deployment tests check persistent home coverage. A system
build does not establish that an actual login unlocks the keyring. Verify unlock,
application access, and credential survival across reboot after installation.

## Validation

Composition tests cover profile selection, package coherence including overrides,
session ownership, multiple Home Manager users, and the generated configuration.
Builds and `Hyprland --verify-config` validate artifacts and configuration syntax;
they do not establish graphical startup, physical monitor behavior, or live Home
Manager activation. Those remain separate boot-time acceptance checks.
