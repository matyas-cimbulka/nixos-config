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

with subtest("numbered workspace bindings"):
    pella.send_key("meta_l-5")
    pella.wait_until_succeeds(as_user("hyprctl -j -i 0 activeworkspace") + " | jq -e '.id == 5'")
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
