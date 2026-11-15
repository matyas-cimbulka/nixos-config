# Workstation desktop

The workstation profiles select Hyprland, Ghostty, Noctalia, Noctalia Greeter, and GNOME Keyring.
Noctalia provides the bar, launcher, control center, notifications, Polkit agent,
wallpaper, and password lock screen. Noctalia Greeter provides graphical password
login through greetd. Installation remains deferred.

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
| Super + 1–5 | Switch to a persistent workspace |
| Super + Shift + 1–5 | Move the focused window to a workspace |
| Super + Space | Open or close the Noctalia launcher |
| Super + S | Open or close the control center |
| Super + Comma | Open or close Noctalia settings |
| Super + L | Lock the session |
| Volume keys | Adjust or mute output volume |

On the NixOS workstation, terminal launch uses `uwsm app` and logout uses
`uwsm stop`. The standalone configuration uses normal compositor dispatchers.
Ghostty's appearance is managed by the Matyas Ghostty Home Manager module, which
also installs Fira Code Nerd Font for the configured font family.

## Noctalia ownership and appearance

The NixOS workstation profile explicitly selects the `noctalia` feature. It uses
the native NixOS module for system integration and recommended NetworkManager,
Bluetooth, UPower, and power-profile services. The feature also enables PipeWire
with ALSA/PulseAudio compatibility, RTKit, and Polkit through overridable defaults.
The native `programs.noctalia.recommendedServices.enable` flag allows opting out of
the recommended integrations; individual native service options remain overridable.

Matyas's workstation home explicitly selects `matyas-desktop-noctalia`. Home Manager
owns the per-user service, bound to the graphical session; the NixOS Noctalia
service launcher stays disabled. Shared Home Manager delivery defaults each enabled
home to the final NixOS Noctalia package, including system package overrides.
An explicit personal package override takes precedence. Standalone homes install
their own package. Noctalia adds its Hyprland shortcuts and appearance only when
both features are enabled, with no second compositor startup command.

The baseline uses Catppuccin's dark Mocha colors, Inter for shell text, floating
pill groups across the top, workspaces 1–5, a centered clock, and tray/system
controls at the right. The dock is disabled. Rounded windows and dark floating
panels take inspiration from [BnSplit's desktop](https://github.com/bnsplits/dotfiles).
The background is an original subtle dark gradient, rendered from the repository's
SVG source to PNG during the build; no external wallpaper is downloaded at runtime.
The control center floats with an opaque background independently of the
transparent bar, keeping application text from showing through it. Hyprland's
default wallpaper and splash are disabled; a plain dark background appears while
Noctalia loads the gradient.

Home Manager writes and validates `~/.config/noctalia/config.toml`. UI changes are
saved separately in `~/.local/state/noctalia/settings.toml` and take precedence.
Both are covered by pella's persistent home. Experiment in the UI, then move useful
settings into Nix and remove the corresponding UI override when it should defer
to the baseline. Noctalia's theme templates are not configured to rewrite Ghostty
or other Home Manager files.

The pinned Noctalia lock screen authenticates through the existing `login` PAM
stack. Manual locking and lock-before-suspend use Noctalia's native behavior;
automatic idle timeouts retain the upstream disabled defaults. Password login is
also how GNOME Keyring is unlocked. The preview therefore uses its VM-only account
password rather than automatic login, and the runtime test checks the actual
Secret Service collection is unlocked before exercising desktop features.

## Graphical login

The workstation profile explicitly selects the `noctalia-greeter` feature, using
the pinned native NixOS module and package. greetd runs the login screen as the
unprivileged `greeter` account. When Hyprland is enabled, the feature selects its
registered session, including `hyprland-uwsm` when UWSM is enabled. There is no
automatic login. Disabling `services.displayManager.noctalia-greeter.enable`
removes the greeter and its appearance integration.

UWSM's supported quiet-start mode keeps normal startup messages off the console
during the greeter-to-desktop handoff while retaining them in the journal. Set
`environment.sessionVariables.UWSM_SILENT_START = "0"` to opt back into console
output. A brief blank screen during compositor handoff can still occur.

No account is pinned: upstream shows an account picker when multiple login
accounts exist and opens the password step when only one account exists. The
workstation profile supplies a dark Catppuccin baseline, the same built gradient
as the personal desktop, and a system-installed Inter font that the greeter can
read before login. Monitor modes and scaling retain automatic upstream defaults.
The greeter also gets a system-readable Adwaita cursor theme at size 24, independent
of the user's desktop settings. The preview forces software cursors for its virtual
GPU; production keeps normal hardware cursor support.

The default greeter package carries a small fix for version 1.7: relayout must
preserve a mouse press when there are no popup menus to remove. This prevents the
first click on a control from being lost when it takes focus from the password
field. Remove the patch once the upstream package includes an equivalent fix;
the runtime test opens the appearance menu with its first click.

The native module supplies the declarative `greeter.toml`. UI and appearance-sync
state use writable `sync.toml`; explicit Nix values take precedence. Appearance
sync remains administrator-authenticated, and automatic sync is not enabled.
Pella persists `/var/lib/noctalia-greeter` with the greeter's ownership and mode
0750, plus `/var/lib/AccountsService` for account metadata and avatars, across root
reset. These paths are covered by the existing persistent-state snapshots.

The preview uses this same graphical login. Enter `test-only` for its `matyas`
account. Super+Shift+E logs out and returns to the greeter; Super+L uses the
separate Noctalia session lock screen.

## Desktop keyring

The workstation profile explicitly selects the NixOS `gnome-keyring` feature.
The native service supplies a Secret Service provider and optional PAM hooks in
the login PAM stack to unlock and start the login keyring. The greetd greeter
inherits that stack; it does not need duplicate keyring hooks. The native
`services.gnome.gnome-keyring.enable` option allows opting out. Servers do not
select this feature.

GNOME Keyring stores local desktop application credentials; 1Password remains
the personal vault and installation recovery-key custodian. Keyring files normally
live in `~/.local/share/keyrings`, covered by pella's persistent `/home` subvolume.
Keep the Login keyring as the default collection for Noctalia's Secret
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

Use `nix run .#desktop-preview` on x86_64 Linux to inspect the desktop in a
disposable QEMU VM before installation. The preview shares the actual workstation
profile and personal Home Manager settings, including future Noctalia changes.
Both preview screens are fixed at 1920x1080 with scale 1, using guest software
rendering and cursors. The physical workstation keeps automatic monitor detection
and normal renderer and cursor selection.
It has separate virtual storage and test credentials, and never activates the
physical workstation. See the [desktop testing guide](../tests/README.md#desktop-preview-and-runtime-test)
for screenshots, saved preview state, automated checks, and remote-builder requirements.

Composition tests cover profile selection, package coherence including overrides,
session ownership, multiple Home Manager users, and the generated configuration.
The desktop VM test exercises graphical login, keyring unlock, Noctalia startup,
shell and workspace shortcuts, notification delivery, UI overrides across restart,
password locking, and logout back to the greeter. It rejects incorrect passwords
at both login and lock screens. Its screenshots support visual review of the
greeter, bar, launcher, controls, and lock screen.
Builds and `Hyprland --verify-config` validate artifacts and configuration syntax;
they do not establish graphical startup, physical monitor behavior, or live Home
Manager activation. Those remain separate boot-time acceptance checks.
