"""Exercise installer failure/reinstall handling without privileged writes."""
from pathlib import Path
import subprocess
import os
import tempfile
import unittest


MODULE = Path(__file__).parents[1] / "module.sh"


class InstallTests(unittest.TestCase):
    def install(self, registered=False, fail_build=False):
        # All mutating commands are shell functions; sysfs/header paths
        # are redirected to a temporary fixture before sourcing the manifest.
        script = r'''
source "$1"
MODULE_DIR=/fixture
warn() { :; }
cat() { echo 'ASUS EXPERTBOOK B9406CAA'; }
uname() { echo 7.2.3-arch1-3; }
command() { return 0; }
install() { echo 'write-source'; }
modprobe() { echo 'load-driver'; }
mod_install_files() { echo 'publish-config'; }
dkms() {
  if [[ $1 == status ]]; then
    [[ $REGISTERED == 1 ]] && echo installed
    return 0
  fi
  echo "dkms-$1"
  if [[ $1 == install && $FAIL_BUILD == 1 ]]; then return 42; fi
}
module_install
'''
        environment = dict(os.environ, REGISTERED=str(int(registered)),
                           FAIL_BUILD=str(int(fail_build)))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            headers = root / 'lib/modules/7.2.3-arch1-3/build'
            headers.mkdir(parents=True)
            (headers / 'Makefile').touch()
            (root / 'sys/module/b9406_mute_led').mkdir(parents=True)
            source = MODULE.read_text().replace('/sys/', str(root / 'sys') + '/')
            source = source.replace('/lib/modules/', str(root / 'lib/modules') + '/')
            manifest = root / 'module.sh'
            manifest.write_text(source)
            return subprocess.run(["bash", "-c", script, "test", str(manifest)],
                                  env=environment, text=True, capture_output=True)

    def test_failed_build_does_not_publish_boot_or_service_config(self):
        result = self.install(fail_build=True)
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertNotIn('load-driver', result.stdout)
        self.assertNotIn('publish-config', result.stdout)

    def test_reinstall_reuses_registered_dkms_source(self):
        result = self.install(registered=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('dkms-add', result.stdout)
        self.assertIn('dkms-install', result.stdout)
        self.assertIn('publish-config', result.stdout)


if __name__ == '__main__':
    unittest.main()
