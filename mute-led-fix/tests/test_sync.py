import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("led_sync", Path(__file__).parents[1] / "sync.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class SyncTests(unittest.TestCase):
    def check_routing(self, omarchy):
        sink_query = (("omarchy-audio-output-sink",) if omarchy
                      else ("pactl", "get-default-sink"))
        answers = {
            sink_query: "physical-speaker",
            ("pactl", "get-sink-mute", "physical-speaker"): "Mute: no",
            ("pactl", "get-source-mute", "@DEFAULT_SOURCE@"): "Mute: yes",
        }
        with patch.object(sync.shutil, "which", return_value=omarchy), \
             patch.object(sync, "run", side_effect=lambda *a: answers[a]), \
             patch.object(sync, "update") as update:
            sync.sync()
        self.assertEqual(update.call_args_list, [
            unittest.mock.call("platform::mute", False),
            unittest.mock.call("platform::micmute", True),
        ])

    def test_omarchy_uses_physical_output_helper(self):
        self.check_routing("/usr/bin/omarchy-audio-output-sink")

    def test_other_desktops_use_default_sink(self):
        self.check_routing(None)

    def test_led_writes_only_when_out_of_sync(self):
        with patch.object(sync.Path, "exists", return_value=True), \
             patch.object(sync.Path, "read_text", return_value="0\n"), \
             patch.object(sync, "run") as run:
            sync.update("platform::mute", False)
            run.assert_not_called()
            sync.update("platform::mute", True)
            run.assert_called_once_with("brightnessctl", "--device=platform::mute", "set", "1")

    def test_absent_led_is_skipped(self):
        with patch.object(sync.Path, "exists", return_value=False), \
             patch.object(sync, "run") as run:
            sync.update("platform::mute", True)
            run.assert_not_called()

    def test_disconnected_server_does_not_change_leds(self):
        with patch.object(sync, "run", side_effect=subprocess.CalledProcessError(1, "pactl")), \
             patch.object(sync, "update") as update:
            with self.assertRaises(subprocess.CalledProcessError):
                sync.sync()
            update.assert_not_called()


if __name__ == "__main__":
    unittest.main()
