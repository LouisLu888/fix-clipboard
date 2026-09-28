#!/usr/bin/env python3
"""Safe tests by default; --fault-injection pauses the current user's useractivityd."""
import importlib.util
import json
import plistlib
import argparse, os, pathlib, signal, subprocess, sys, time, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / 'dist/Fix Clipboard.app/Contents/MacOS/FixClipboard'

def run(*args, check=True):
    return subprocess.run(args, text=True, capture_output=True, timeout=15, check=check)

def identity(pid):
    p = run('/bin/ps', '-p', str(pid), '-o', 'uid=,lstart=,comm=', check=False)
    return p.stdout.strip() if p.returncode == 0 else None

def stopped(pid):
    return 'T' in run('/bin/ps', '-p', str(pid), '-o', 'stat=', check=False).stdout

class SafeTests(unittest.TestCase):
    def test_commerce_and_icon_resources(self):
        resources = APP.parents[1] / 'Resources'
        config = json.loads((resources / 'Commerce.json').read_text())
        self.assertEqual(set(config), {'storeID', 'productID', 'variantID', 'checkoutURL', 'priceLabel', 'deviceLimit', 'testMode', 'manualPublicKey'})
        self.assertGreater(config['deviceLimit'], 0)
        self.assertIsInstance(config['testMode'], bool)
        self.assertEqual(config, json.loads((ROOT / 'config/Commerce.json').read_text()))
        self.assertGreater((resources / 'AppIcon.icns').stat().st_size, 0)
    def test_bounded_subprocess(self):
        self.assertIn('PASS: bounded subprocess', run(str(APP), '--process-self-test').stdout)
    def test_release_configuration_guards(self):
        spec = importlib.util.spec_from_file_location('release_check', ROOT / 'scripts/release_check.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        config = json.loads((ROOT / 'config/Commerce.json').read_text())
        self.assertEqual(module.problems(config), [])
        self.assertEqual(module.problems(config, production=True), [])
        self.assertTrue(module.problems(dict(config, manualPublicKey="bad"), production=True))
        self.assertTrue((resources := APP.parents[1] / "Resources" / "WeChatQR.jpg").exists())
        sample = dict(config, testMode=True)
        sample.pop("manualPublicKey", None)
        self.assertTrue(module.problems(sample, production=True))
        self.assertEqual(module.problems(dict(sample, testMode=False), production=True), [])
        self.assertTrue(module.problems(dict(sample, checkoutURL='http://attacker.example/checkout/buy/x')))
        self.assertTrue(module.problems(dict(sample, storeID=True)))
    def test_license_flows(self):
        self.assertIn("license regression assertions", run(str(APP), "--license-self-test").stdout)
    def test_repair_and_schedule(self):
        self.assertIn('PASS:', run(str(APP), '--self-test').stdout)
    def test_real_network_callback(self):
        self.assertIn('callback received', run(str(APP), '--network-test').stdout)
    def test_universal_binary(self):
        result = run('/usr/bin/lipo', '-archs', str(APP)).stdout
        self.assertIn('arm64', result)
        self.assertIn('x86_64', result)
    def test_bluetooth_privacy_declaration(self):
        with (APP.parents[1] / 'Info.plist').open('rb') as f:
            info = plistlib.load(f)
        self.assertTrue(info.get('NSBluetoothAlwaysUsageDescription', '').strip())
    def test_diagnostics(self):
        output = run(str(APP), '--diagnostics').stdout
        for label in ['Wi-Fi', 'Bluetooth', 'Handoff', 'VPN']:
            self.assertIn(label, output)
    def test_bundle_signature(self):
        run('/usr/bin/codesign', '--verify', '--strict', str(APP.parents[2]))

class FaultTests(unittest.TestCase):
    def test_stopped_service_recovery(self):
        pids = run('/usr/bin/pgrep', '-u', str(os.getuid()), '-x', 'useractivityd').stdout.split()
        self.assertEqual(len(pids), 1, 'Need exactly one current-user daemon; no fault injected')
        pid = int(pids[0]); before = identity(pid)
        self.assertTrue(before and 'useractivityd' in before)
        self.assertFalse(stopped(pid), 'Already stopped; do not disturb existing diagnostic state')
        # Independent process is armed and acknowledges readiness BEFORE SIGSTOP.
        watchdog = subprocess.Popen([sys.executable, __file__, '--watchdog', str(pid), before],
                                    stdout=subprocess.PIPE, text=True, start_new_session=True)
        self.assertEqual(watchdog.stdout.readline().strip(), 'ARMED')
        try:
            os.kill(pid, signal.SIGSTOP)
            time.sleep(.2)
            self.assertTrue(stopped(pid), 'Fault injection did not take effect')
            result = run(str(APP), '--repair-test', check=False)
            deadline = time.monotonic() + 3
            while identity(pid) == before and time.monotonic() < deadline:
                time.sleep(.1)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotEqual(identity(pid), before,
                'Repair reported success but the original paused daemon is still present')
            # useractivityd is demand-started. Explicit activation here verifies launchability,
            # not that the application itself guarantees a replacement process is running.
            run('/bin/launchctl', 'kickstart', f'gui/{os.getuid()}/com.apple.coreservices.useractivityd')
            deadline = time.monotonic() + 5
            new = []
            while time.monotonic() < deadline:
                new = run('/usr/bin/pgrep', '-u', str(os.getuid()), '-x', 'useractivityd', check=False).stdout.split()
                if new: break
                time.sleep(.1)
            self.assertTrue(new, 'Daemon did not become available after demand activation')
            self.assertTrue(all(not stopped(int(p)) for p in new))
            print('Recovered service after demand activation; cross-device clipboard NOT tested.')
        finally:
            if identity(pid) == before:
                os.kill(pid, signal.SIGCONT)
            # Watchdog remains independent until its short deadline, then exits itself.

if __name__ == '__main__':
    if '--watchdog' in sys.argv:
        pid = int(sys.argv[2]); before = sys.argv[3]
        print('ARMED', flush=True)
        time.sleep(12)
        if identity(pid) == before:
            try: os.kill(pid, signal.SIGCONT)
            except ProcessLookupError: pass
        sys.exit(0)
    parser = argparse.ArgumentParser()
    parser.add_argument('--fault-injection', action='store_true', help='Temporarily pause useractivityd; interrupts Handoff')
    args = parser.parse_args()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(SafeTests)
    if args.fault_injection: suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(FaultTests))
    sys.exit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
