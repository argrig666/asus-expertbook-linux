"""Regressions for disconnected evdev devices and sysfs LED notifications."""

import errno
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import select
import tempfile
import unittest
from unittest.mock import Mock, patch


SOURCE = Path(__file__).resolve().parents[1] / "keyboard-backlight-auto/kbd-backlight-auto"
loader = importlib.machinery.SourceFileLoader("kbd_backlight_auto", str(SOURCE))
spec = importlib.util.spec_from_loader(loader.name, loader)
kbd = importlib.util.module_from_spec(spec)
loader.exec_module(kbd)


class EventMonitorTests(unittest.TestCase):
    def setUp(self):
        self.monitor = kbd.EventMonitor("/nonexistent-led", True)
        self.log = patch.object(kbd, "log").start()
        self.writers = []
        self.addCleanup(patch.stopall)
        self.addCleanup(self.cleanup)

    def cleanup(self):
        self.monitor.close()
        for fd in self.writers:
            os.close(fd)

    def pipe(self, kind="key"):
        reader, writer = os.pipe2(os.O_NONBLOCK)
        self.monitor.fds[reader] = ("/dev/input/test", kind)
        self.monitor.poller.register(reader, select.POLLIN)
        self.writers.append(writer)
        return reader, writer

    def test_real_disconnect_removes_fd_and_next_poll_sleeps(self):
        reader, writer = self.pipe()
        os.close(writer)
        self.writers.remove(writer)
        self.assertEqual(self.monitor.events(0), [])
        self.assertNotIn(reader, self.monitor.fds)
        with self.assertRaises(OSError):
            os.fstat(reader)
        # A dead evdev fd used to wake this poll immediately forever.
        import time
        start = time.monotonic()
        self.monitor.events(0.02)
        self.assertGreaterEqual(time.monotonic() - start, 0.015)

    def test_enodev_removes_fd_even_without_hangup_mask(self):
        reader, _writer = self.pipe()
        self.monitor.poller = Mock()
        self.monitor.poller.poll.return_value = [(reader, select.POLLIN)]
        with patch.object(kbd.os, "read", side_effect=OSError(errno.ENODEV, "gone")):
            self.assertEqual(self.monitor.events(0), [])
        self.assertNotIn(reader, self.monitor.fds)

    def test_pollnval_on_already_closed_fd_does_not_crash(self):
        reader, _writer = self.pipe()
        os.close(reader)
        self.assertEqual(self.monitor.events(0), [])
        self.assertNotIn(reader, self.monitor.fds)

    def test_eof_removes_fd(self):
        reader, _writer = self.pipe()
        self.monitor.poller = Mock()
        self.monitor.poller.poll.return_value = [(reader, select.POLLIN)]
        with patch.object(kbd.os, "read", return_value=b""):
            self.monitor.events(0)
        self.assertNotIn(reader, self.monitor.fds)

    def test_eagain_keeps_live_device(self):
        reader, _writer = self.pipe()
        self.monitor.poller = Mock()
        self.monitor.poller.poll.return_value = [(reader, select.POLLIN)]
        with patch.object(kbd.os, "read", side_effect=BlockingIOError(errno.EAGAIN, "retry")):
            self.monitor.events(0)
        self.assertIn(reader, self.monitor.fds)

    def test_sysfs_pollerr_with_pollpri_is_a_valid_notification(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "brightness_hw_changed"
            path.write_text("3\n")
            self.monitor.watch(str(path), "hardware")
            reader = next(iter(self.monitor.fds))
            self.monitor.poller = Mock()
            self.monitor.poller.poll.return_value = [
                (reader, select.POLLPRI | select.POLLERR)]
            self.assertEqual(self.monitor.events(0), [("hardware", 3)])
            self.assertIn(reader, self.monitor.fds)

    def test_unreadable_sysfs_notification_is_disarmed(self):
        reader, _writer = self.pipe("hardware")
        self.monitor.poller = Mock()
        self.monitor.poller.poll.return_value = [(reader, select.POLLERR)]
        with patch.object(kbd.os, "lseek"), patch.object(
                kbd.os, "read", side_effect=OSError(errno.ENODATA, "no data")):
            self.assertEqual(self.monitor.events(0), [])
        self.assertNotIn(reader, self.monitor.fds)

    def test_rescan_is_bounded_and_reopens_disconnected_path(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "event"
            path.touch()
            with patch.object(kbd, "find_illum_key_devices", return_value=[{"event": str(path)}]), \
                    patch.object(kbd, "find_lid_device", return_value=None), \
                    patch.object(kbd.time, "monotonic", return_value=10.0) as clock:
                self.monitor.scan()
                reader = next(iter(self.monitor.fds))
                self.monitor.drop(reader)
                self.monitor.scan()
                self.assertEqual(self.monitor.fds, {})
                clock.return_value = 15.0
                self.monitor.scan()
                self.assertEqual(len(self.monitor.fds), 1)

    def test_lid_and_fn_key_events_survive_batch_reads(self):
        lid, lid_writer = self.pipe("lid")
        key, key_writer = self.pipe("key")
        os.write(lid_writer, kbd.INPUT_EVENT.pack(0, 0, kbd.EV_SW, kbd.SW_LID, 1))
        os.write(key_writer,
                 kbd.INPUT_EVENT.pack(0, 0, kbd.EV_KEY, kbd.KEY_KBDILLUMUP, 1) +
                 kbd.INPUT_EVENT.pack(0, 0, kbd.EV_KEY, kbd.KEY_KBDILLUMUP, 0))
        self.assertCountEqual(self.monitor.events(0), [("lid", True), ("key", 1)])
        self.assertTrue(self.monitor.has_lid())
        self.monitor.drop(lid)
        self.assertFalse(self.monitor.has_lid())

    def test_poll_rounds_up_fractional_millisecond(self):
        self.monitor.poller = Mock()
        self.monitor.poller.poll.return_value = []
        self.monitor.events(0.0001)
        self.monitor.poller.poll.assert_called_once_with(1)


if __name__ == "__main__":
    unittest.main()
