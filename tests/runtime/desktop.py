import json
import subprocess
import tempfile
import time
import tomllib
from datetime import timedelta
from pathlib import Path
from typing import Any, cast

from test_driver.machine.ocr import perform_ocr_on_screenshot


def as_user(command):
    return (
        "runuser -u matyas -- env XDG_RUNTIME_DIR=/run/user/1000 "
        "PATH=/run/wrappers/bin:/etc/profiles/per-user/matyas/bin:/run/current-system/sw/bin "
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
        f"systemd-run --user --quiet --wait --pipe --collect {command}"
    )


def greeter_text(gravity="center", crop="60%x60%+0+0"):
    # The dark panel needs inversion for reliable OCR. Crop before upscaling
    # to keep this cheaper than the driver's full-screen processing variants.
    with tempfile.TemporaryDirectory() as directory:
        # The test driver's lightweight ImageMagick supports PPM without PNG delegates.
        screenshot = Path(directory) / "greeter.ppm"
        prepared = Path(directory) / "text.ppm"
        pella.send_monitor_command(f"screendump {screenshot}")
        subprocess.run([
            "magick", str(screenshot), "-gravity", gravity, "-crop", crop,
            "+repage", "-colorspace", "Gray", "-negate", "-resize", "200%", str(prepared),
        ], check=True)
        return " ".join(perform_ocr_on_screenshot(prepared).split()).lower()


def click_at(x, y):
    assert pella.qmp_client is not None
    # QMP supports structured event arguments; the driver's annotation only lists strings.
    qmp = cast(Any, pella.qmp_client)
    qmp.send("input-send-event", {"events": [
        {"type": "abs", "data": {"axis": "x", "value": round(x * 32767 / 1920)}},
        {"type": "abs", "data": {"axis": "y", "value": round(y * 32767 / 1080)}},
    ]})
    # Let the software-rendered greeter present the first pointer-enter frame.
    time.sleep(1)
    for down in [True, False]:
        qmp.send("input-send-event", {"events": [
            {"type": "btn", "data": {"down": down, "button": "left"}},
        ]})
        time.sleep(0.1)


start_all()
pella.wait_for_unit("home-manager-matyas.service")
pella.succeed("test -e /home/matyas/.config/systemd/user/noctalia.service")
with subtest("graphical greeter and password login"):
    pella.wait_for_unit("greetd.service")
    retry(lambda _: "password" in greeter_text(), timeout=timedelta(seconds=30))
    assert "matyas" in greeter_text()
    pella.screenshot("greeter")
    # Open the appearance menu without changing its selection, then focus the password.
    click_at(1875, 30)
    retry(lambda _: "dracula" in greeter_text("northeast", "15%x30%+0+0"), timeout=timedelta(seconds=30))
    pella.screenshot("greeter-pointer-menu")
    pella.send_key("esc")
    click_at(900, 578)
    pella.send_chars("wrong-test-password")
    pella.send_key("ret")
    retry(lambda _: "autherr" in greeter_text().replace("_", "").replace(" ", ""), timeout=timedelta(seconds=30))
    pella.screenshot("greeter-rejected-password")
    pella.succeed("! pgrep -u matyas -x Hyprland")
    pella.send_chars("test-only")
    pella.send_key("ret")
pella.wait_until_succeeds("systemctl is-active user@1000.service")
pella.wait_until_succeeds(as_user("systemctl --user is-active graphical-session.target"))
pella.wait_until_succeeds(as_user("systemctl --user is-active noctalia.service"))
pella.wait_until_succeeds(as_user("noctalia msg status") + " | jq -e '.barVisible'")
pella.succeed(as_user("python3 /etc/desktop-test/keyring.py"))
pella.fail("grep -a -q 'Selected compositor ID:' /dev/vcs1")
pella.succeed("journalctl -b -t uwsm --no-pager | grep -F 'Selected compositor ID:'")
pella.wait_until_succeeds(as_user("hyprctl -j -i 0 monitors"))
monitors = json.loads(pella.succeed(as_user("hyprctl -j -i 0 monitors")))
assert len(monitors) == 1, monitors
assert monitors[0]["width"] == 1920 and monitors[0]["height"] == 1080, monitors
pella.screenshot("desktop")

with subtest("password app, tray, and session-wide agent configuration"):
    pella.wait_until_succeeds(as_user("systemctl --user is-active onepassword.service"))
    pella.wait_until_succeeds(as_user("python3 /etc/desktop-test/tray.py"))
    assert "/home/matyas/.1password/agent.sock" in pella.succeed(as_user("printenv SSH_AUTH_SOCK"))
    assert "identityagent /home/matyas/.1password/agent.sock" in pella.succeed(as_user("ssh -G github.com"))
    pella.succeed("test -g /run/wrappers/bin/1Password-BrowserSupport; test -g /run/wrappers/bin/op")
    pella.succeed(as_user("op --version"))

with subtest("unprivileged Nix survives reboot with stale borrowed-store metadata"):
    pella.succeed(as_user("cp -rL /etc/desktop-test/nix /home/matyas/nix-probe"))
    pella.succeed(as_user("chmod u+w /home/matyas/nix-probe"))
    # Model a previously registered path borrowed from the host, rather than a guest-created path.
    pella.succeed(f"nix-store --load-db < {borrowed_registration}")
    command = "nix run --offline --option eval-cache false /home/matyas/nix-probe"
    assert "Desktop Nix works" in pella.succeed(as_user(command))
    probe_output = pella.succeed(as_user("nix path-info --offline /home/matyas/nix-probe")).strip()
    source_name = Path(borrowed_source).name
    pella.succeed(f"test -f /nix/.ro-store/{source_name} && test ! -e /nix/.rw-store/upper/{source_name}")
    # Check isolation before asking the guest daemon to delete this unreferenced fixture.
    assert set(pella.succeed("findmnt -n -o FSTYPE -T /nix/store").split()) == {"overlay"}
    assert pella.succeed("findmnt -n -o OPTIONS -T /nix/.ro-store").strip().startswith("ro,")
    assert pella.succeed("findmnt -n -o FSTYPE -T /nix/.rw-store/upper").strip() == "ext4"
    pella.succeed(f"nix-store --store daemon --delete {borrowed_source}")
    # Reload the old record to model a persisted DB after a borrowed path disappears.
    pella.succeed(f"nix-store --load-db < {borrowed_registration}")
    pella.succeed(f"test -f /nix/.ro-store/{source_name} && nix-store --check-validity {borrowed_source}")
    failure = pella.fail(as_user(command) + " 2>&1")
    assert "does not exist" in failure and source_name in failure, failure
    pella.shutdown()
    pella.start()
    pella.wait_for_unit("greetd.service")
    retry(lambda _: "password" in greeter_text(), timeout=timedelta(seconds=30))
    pella.send_chars("test-only")
    pella.send_key("ret")
    pella.wait_until_succeeds("systemctl is-active user@1000.service")
    pella.wait_until_succeeds(as_user("systemctl --user is-active graphical-session.target"))
    pella.wait_until_succeeds(as_user("noctalia msg status") + " | jq -e '.barVisible'")
    # Retaining the previous output must not depend on silently rebuilding it.
    pella.succeed(f"test -x {probe_output}/bin/desktop-preview-nix-probe && nix-store --check-validity {probe_output}")
    assert "Desktop Nix works" in pella.succeed(as_user(command))

with subtest("real terminal binding and keyboard input"):
    assert json.loads(pella.succeed(as_user("hyprctl -j -i 0 getoption general:layout")))["str"] == "scrolling"
    pella.send_key("meta_l-ret")
    pella.wait_until_succeeds(
        as_user("hyprctl -j -i 0 clients")
        + " | jq -e 'any(.[]; .class == \"com.mitchellh.ghostty\")'"
    )
    # Split the marker so OCR must find command output, not the echoed input line.
    pella.send_chars("printf 'Desktop '; printf 'preview '; printf 'ready\\n'; touch /tmp/desktop-preview-ready")
    pella.send_key("ret")
    pella.wait_for_file("/tmp/desktop-preview-ready")
    # The unprocessed screenshot is sufficient for this large terminal text;
    # avoid the driver's expensive upscaled OCR variants on remote builders.
    retry(lambda _: "Desktop preview ready" in pella.get_screen_text(), timeout=timedelta(seconds=30))
    pella.screenshot("ghostty")

with subtest("scrolling layout and directional window focus"):
    original = json.loads(pella.succeed(as_user("hyprctl -j -i 0 activewindow")))["address"]
    for count in [2, 3]:
        pella.send_key("meta_l-ret")
        pella.wait_until_succeeds(as_user("hyprctl -j -i 0 clients")
            + f" | jq -e '[.[] | select(.class == \"com.mitchellh.ghostty\")] | length == {count}'", timeout=30)
        # A mapped GTK window can precede shell startup. Wait for Fish's title
        # before requesting the next single-instance Ghostty window.
        pella.wait_until_succeeds(as_user("hyprctl -j -i 0 clients")
            + " | jq -e 'all(.[] | select(.class == \"com.mitchellh.ghostty\"); .title != \"Ghostty\")'", timeout=30)
    last = json.loads(pella.succeed(as_user("hyprctl -j -i 0 activewindow")))["address"]
    columns = [client for client in json.loads(pella.succeed(as_user("hyprctl -j -i 0 clients")))
        if client["class"] == "com.mitchellh.ghostty"]
    assert all(0.4 * 1920 < client["size"][0] < 0.6 * 1920 and client["size"][1] > 900 for client in columns), columns
    assert any(client["at"][0] < 0 or client["at"][0] + client["size"][0] > 1920 for client in columns), columns
    pella.screenshot("scrolling-layout")
    # Include another workspace in the native, vertically stacked overview.
    pella.send_key("meta_l-3")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activeworkspace") + " | jq -e '.id == 3'")
    pella.send_key("meta_l-ret")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 clients")
        + " | jq -e 'any(.[]; .class == \"com.mitchellh.ghostty\" and .workspace.id == 3)'")
    pella.send_key("meta_l-1")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activeworkspace") + " | jq -e '.id == 1'")
    pella.send_key("meta_l-tab")
    overview = as_user("hyprctl -i 0 submap") + " | grep -x scrolloverview"
    pella.wait_until_succeeds(overview)
    plugins = json.loads(pella.succeed(as_user("hyprctl -j -i 0 plugin list")))
    assert any(plugin["name"] == "scrolloverview" for plugin in plugins), plugins
    assert not pella.succeed(as_user("hyprctl -i 0 configerrors")).strip()
    pella.succeed(as_user("hyprctl -j -i 0 layers")
        + " | jq -e '[.. | objects | select(.namespace? == \"noctalia-window-switcher\")] | length == 0'")
    # The submap becomes active before the overview animation finishes.
    time.sleep(1)
    pella.screenshot("window-overview")
    pella.send_key("left")
    pella.send_key("left")
    pella.send_key("ret")
    pella.wait_until_fails(overview)
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activewindow") + f" | jq -e '.address == \"{original}\"'")
    focused = json.loads(pella.succeed(as_user("hyprctl -j -i 0 activewindow")))
    assert focused["size"] == next(client["size"] for client in columns if client["address"] == original), focused
    # Down traverses the empty persistent workspace 2 to workspace 3. This must
    # select a real window on that workspace when the overview closes.
    pella.send_key("meta_l-tab")
    pella.wait_until_succeeds(overview)
    pella.send_key("down")
    pella.send_key("down")
    time.sleep(1)
    pella.screenshot("stacked-workspaces")
    pella.send_key("ret")
    pella.wait_until_fails(overview)
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activeworkspace") + " | jq -e '.id == 3'")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activewindow") + " | jq -e '.workspace.id == 3'")
    pella.send_key("meta_l-tab")
    pella.wait_until_succeeds(overview)
    pella.send_key("esc")
    pella.wait_until_fails(overview)
    pella.send_key("meta_l-1")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activeworkspace") + " | jq -e '.id == 1'")
    pella.send_key("meta_l-right")
    pella.send_key("meta_l-right")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activewindow") + f" | jq -e '.address == \"{last}\"'")
    pella.send_key("meta_l-tab")
    pella.wait_until_succeeds(overview)
    # At half scale the first column is at the left of the centered row.
    # This exercises the custom submap's pointer-selection dispatcher too.
    click_at(240, 550)
    pella.wait_until_fails(overview)
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activewindow") + f" | jq -e '.address == \"{original}\"'")
    pella.send_key("meta_l-3")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activeworkspace") + " | jq -e '.id == 3'")
    pella.send_key("meta_l-q")
    pella.send_key("meta_l-1")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activeworkspace") + " | jq -e '.id == 1'")
    pella.send_key("meta_l-right")
    pella.send_key("meta_l-right")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activewindow") + f" | jq -e '.address == \"{last}\"'")
    pella.send_key("meta_l-left")
    pella.send_key("meta_l-left")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activewindow") + f" | jq -e '.address == \"{original}\"'")
    focused = json.loads(pella.succeed(as_user("hyprctl -j -i 0 activewindow")))
    assert focused["at"][0] >= 0 and focused["at"][0] + focused["size"][0] <= 1920, focused
    pella.send_key("meta_l-right")
    pella.send_key("meta_l-right")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activewindow") + f" | jq -e '.address == \"{last}\"'")
    for count in [2, 1]:
        pella.send_key("meta_l-q")
        pella.wait_until_succeeds(as_user("hyprctl -j -i 0 clients")
            + f" | jq -e '[.[] | select(.class == \"com.mitchellh.ghostty\")] | length == {count}'")
    assert json.loads(pella.succeed(as_user("hyprctl -j -i 0 activewindow")))["address"] == original

with subtest("day-one applications and editable editor settings"):
    assert "google-chrome.desktop" in pella.succeed(as_user("xdg-mime query default x-scheme-handler/https"))
    assert "org.gnome.Nautilus.desktop" in pella.succeed(as_user("xdg-mime query default inode/directory"))
    pella.succeed(as_user("systemd-run --user --collect --quiet uwsm app -- google-chrome --no-first-run --no-default-browser-check file:///etc/desktop-test/browser.html"))
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 clients") + " | jq -e 'any(.[]; .title | contains(\"Pella browser check\"))'", timeout=60)
    browser = next(client for client in json.loads(pella.succeed(as_user("hyprctl -j -i 0 clients"))) if "Pella browser check" in client["title"])
    assert not browser["xwayland"], browser
    pella.screenshot("chrome")
    pella.send_key("meta_l-q")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 clients") + " | jq -e 'all(.[]; .title | contains(\"Pella browser check\") | not)'", timeout=30)
    settings_path = "/home/matyas/.config/Code/User/settings.json"
    pella.succeed(as_user(f"test -w {settings_path}"))
    settings = json.loads(pella.succeed(f"cat {settings_path}"))
    assert settings["nix.enableLanguageServer"] and settings["workbench.colorTheme"] == "Catppuccin Mocha", settings
    extensions = pella.succeed(as_user("code --list-extensions"))
    assert "jnoortheen.nix-ide" in extensions and "mkhl.direnv" in extensions, extensions
    # Use the same session scopes as desktop launchers; a short-lived service can
    # kill Electron children when its CLI exits. Skip account onboarding in tests.
    pella.succeed(as_user("systemd-run --user --collect --quiet uwsm app -- code --new-window --skip-welcome --skip-release-notes /etc/desktop-test/editor.nix"))
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 clients") + " | jq -e 'any(.[]; (.class | ascii_downcase) == \"code\")'", timeout=60)
    editor = next(client for client in json.loads(pella.succeed(as_user("hyprctl -j -i 0 clients"))) if client["class"].lower() == "code")
    assert not editor["xwayland"], editor
    retry(lambda _: "Workstation editor ready" in pella.get_screen_text(), timeout=timedelta(seconds=60))
    # A first file opens in Restricted Mode. Trust this known fixture through the
    # same UI a user uses for their own code; retain production's trust prompts.
    retry(lambda _: "Restricted Mode" in pella.get_screen_text(), timeout=timedelta(seconds=30))
    # Open trust management from the rendered status bar. Typing into a command
    # palette before its first frame is ready can lose input on slow VM renders.
    click_at(editor["at"][0] + 100, editor["at"][1] + editor["size"][1] - 12)
    try:
        retry(lambda _: "You are in Restricted Mode" in pella.get_screen_text(), timeout=timedelta(seconds=30))
    except Exception:
        pella.screenshot("editor-trust-failure")
        print(pella.get_screen_text())
        raise
    pella.send_key("ctrl-ret")
    # The first window can render before extensions finish loading. Require the
    # configured Nix language server to start for this document as well.
    try:
        pella.wait_until_succeeds(as_user("pgrep -u matyas -x nixd"), timeout=60)
    except Exception:
        print(pella.succeed("find /home/matyas/.config/Code/logs -type f -name '*.log' -exec tail -n 30 {} +"))
        raise
    pella.send_key("esc")
    pella.screenshot("vscode")
    pella.send_key("meta_l-q")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 clients") + " | jq -e 'all(.[]; (.class | ascii_downcase) != \"code\")'", timeout=30)
    pella.succeed(as_user("mkdir -p /home/matyas/FilesReady"))
    pella.send_key("meta_l-e")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 clients") + " | jq -e 'any(.[]; .class == \"org.gnome.Nautilus\")'", timeout=60)
    retry(lambda _: "FilesReady" in pella.get_screen_text(), timeout=timedelta(seconds=30))
    pella.screenshot("nautilus")
    pella.send_key("meta_l-q")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 clients") + " | jq -e 'all(.[]; .class != \"org.gnome.Nautilus\")'", timeout=30)

with subtest("numbered workspace bindings"):
    pella.send_key("meta_l-5")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activeworkspace") + " | jq -e '.id == 5'")
    assert json.loads(pella.succeed(as_user("hyprctl -j -i 0 activeworkspace")))["tiledLayout"] == "scrolling"
    pella.send_key("meta_l-1")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activeworkspace") + " | jq -e '.id == 1'")
    pella.send_key("meta_l-shift-2")
    pella.wait_until_succeeds(
        as_user("hyprctl -j -i 0 clients")
        + " | jq -e 'any(.[]; .class == \"com.mitchellh.ghostty\" and .workspace.id == 2)'"
    )
    pella.send_key("meta_l-1")

with subtest("launcher and control center shortcuts"):
    pella.send_key("meta_l-spc")
    pella.wait_until_succeeds(as_user("noctalia msg status") + " | jq -e '.activePanelId == \"launcher\"'")
    pella.send_chars("ghostty")
    retry(lambda _: "Ghostty" in pella.get_screen_text(), timeout=timedelta(seconds=30))
    pella.screenshot("launcher")
    pella.send_key("esc")
    pella.wait_until_succeeds(as_user("noctalia msg status") + " | jq -e '.panelOpen == false'")
    # Keep an application behind the panel so screenshots reveal transparency problems.
    pella.send_key("meta_l-2")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activeworkspace") + " | jq -e '.id == 2'")
    pella.send_chars("yes '" + "application background " * 6 + "' | head -n 40; touch /tmp/control-center-background")
    pella.send_key("ret")
    pella.wait_for_file("/tmp/control-center-background")
    pella.send_key("meta_l-s")
    pella.wait_until_succeeds(as_user("noctalia msg status") + " | jq -e '.activePanelId == \"control-center\"'")
    pella.screenshot("control-center")
    pella.send_key("esc")
    pella.wait_until_succeeds(as_user("noctalia msg status") + " | jq -e '.panelOpen == false'")

with subtest("desktop notification delivery"):
    pella.succeed(as_user("notify-send -t 15000 'Noctalia preview' 'Notifications work'"))
    retry(lambda _: "Notifications work" in pella.get_screen_text(), timeout=timedelta(seconds=30))
    pella.screenshot("notification")

with subtest("UI overrides survive service restart"):
    baseline = pella.succeed("cat /home/matyas/.config/noctalia/config.toml")
    pella.succeed(as_user("noctalia msg theme-mode-set light"))
    pella.wait_until_succeeds("test -s /home/matyas/.local/state/noctalia/settings.toml")
    pella.succeed(as_user("systemctl --user restart noctalia.service"))
    pella.wait_until_succeeds(as_user("noctalia msg status") + " | jq -e '.barVisible'")
    effective = tomllib.loads(pella.succeed(as_user("noctalia config export full")))
    assert effective["theme"]["mode"] == "light", effective["theme"]
    assert pella.succeed("cat /home/matyas/.config/noctalia/config.toml") == baseline
    pella.succeed(as_user("noctalia msg theme-mode-set dark"))

with subtest("password lock and unlock"):
    pella.send_key("meta_l-l")
    pella.wait_until_succeeds(as_user("noctalia msg status") + " | jq -e '.locked'")
    retry(lambda _: "Password" in pella.get_screen_text(), timeout=timedelta(seconds=30))
    pella.screenshot("lockscreen")
    pella.send_chars("wrong-test-password")
    pella.send_key("ret")
    retry(lambda _: "Authentication fail" in pella.get_screen_text(), timeout=timedelta(seconds=30))
    assert json.loads(pella.succeed(as_user("noctalia msg status")))["locked"]
    pella.send_chars("test-only")
    pella.send_key("ret")
    pella.wait_until_succeeds(as_user("noctalia msg status") + " | jq -e '.locked == false'")

with subtest("logout returns to graphical greeter"):
    pella.send_key("meta_l-shift-e")
    pella.wait_until_succeeds("! pgrep -u matyas -x Hyprland")
    retry(lambda _: "password" in greeter_text(), timeout=timedelta(seconds=30))
    assert "matyas" in greeter_text()
    pella.screenshot("greeter-after-logout")
