#!/usr/bin/python3
"""Mirror session audio mute state to ASUS mute LEDs.

Uses the session audio server and logind (via brightnessctl), without root.
Reconciles once a second, including after resume and audio-server restarts.
Never changes audio state.
"""
import os
from pathlib import Path
import subprocess
import shutil
import time

os.environ["LC_ALL"] = "C"


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL,
                                   timeout=3).strip()


def update(device, muted):
    path = Path("/sys/class/leds") / device / "brightness"
    if path.exists() and path.read_text().strip() != str(int(muted)):
        run("brightnessctl", "--device=" + device, "set", str(int(muted)))


def sync():
    # Same physical sink resolution as Omarchy's output mute shortcut,
    # including EasyEffects passthrough.
    sink = (run("omarchy-audio-output-sink") if shutil.which("omarchy-audio-output-sink")
            else run("pactl", "get-default-sink"))
    if sink:
        update("platform::mute", run("pactl", "get-sink-mute", sink) == "Mute: yes")
    update("platform::micmute",
           run("pactl", "get-source-mute", "@DEFAULT_SOURCE@") == "Mute: yes")


if __name__ == "__main__":
    last_error = None
    while True:
        try:
            sync()
            last_error = None
        except (OSError, subprocess.SubprocessError) as error:
            message = str(error)
            if message != last_error:
                print(message, flush=True)
                last_error = message
        time.sleep(1)
