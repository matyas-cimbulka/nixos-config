import json
from datetime import timedelta


def as_user(command):
    return f"runuser -u matyas -- env XDG_RUNTIME_DIR=/run/user/1000 {command}"


start_all()
pella.wait_for_unit("home-manager-matyas.service")
pella.wait_for_unit("user@1000.service")
pella.wait_until_succeeds(as_user("systemctl --user is-active graphical-session.target"))
pella.wait_until_succeeds(as_user("hyprctl -j -i 0 monitors"))
monitors = json.loads(pella.succeed(as_user("hyprctl -j -i 0 monitors")))
assert len(monitors) == 1, monitors
assert monitors[0]["width"] == 1280 and monitors[0]["height"] == 800, monitors
pella.screenshot("desktop")

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
