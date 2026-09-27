# Test suite

Build: `bash source/build.sh`

Safe default: `python3 tests/test_suite.py`

Covers Swift repair/scheduler regression checks, a real NWPathMonitor initial callback, both binary architectures, and the app signature. The Swift repair checks use fake commands and do not change system state. GitHub Actions runs this safe suite only.

## Opt-in fault injection (real Mac)

`python3 tests/test_suite.py --fault-injection`

This temporarily pauses the current user's useractivityd and invokes the exact repair function used by the menu via `--repair-test`. It may interrupt Handoff. It requires exactly one running, non-paused current-user daemon. It does not read clipboard content.

An independent watchdog acknowledges readiness before SIGSTOP and sends SIGCONT after 12 seconds if the same process identity still exists. A finally block also resumes the process on failure. PID identity includes owner, start time and executable to reduce PID reuse risk. Do not run alongside other service-debugging tools.

The test checks that the original PID identity disappears, then explicitly asks launchd to activate the service and verifies the replacement is not stopped. This proves termination and launchability; it does not prove the app itself eagerly restarts the daemon or that cross-device transfer works. The actual repair enables ClipboardSharingEnabled and does not undo that setting.

## Result: 2026-09-27, Apple Silicon / macOS 26.6.1

Before fix: 4 safe tests passed, fault-injection test failed. SIGTERM returned success but the SIGSTOP-paused daemon remained present. Cleanup resumed it.

After fix: all 5 tests passed. Repair now snapshots original processes, sends SIGTERM, resumes any surviving original process with SIGCONT, and waits up to 2 seconds for those identities to disappear. It reports failure when they remain; it does not escalate to SIGKILL.

No claim of iPhone↔Mac end-to-end success: a human must copy a fresh harmless marker in each direction. Real lid close/open and VPN transition tests are still manual and have not been executed by this suite.

Diagnostics regression cases are included in --self-test: missing/partial Handoff preferences stay unknown; explicit off remains off; Connected is distinguished from Disconnected; query failures remain unknown. On the development Mac, a live read-only diagnostic returned Wi-Fi on, Bluetooth on, Handoff preferences on and system VPN connected. Hardware-off, denied permission and the dialog timeout path have not been tested on-device.
