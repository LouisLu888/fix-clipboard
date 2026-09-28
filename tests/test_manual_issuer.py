"""Isolated seller CLI checks. Never uses the real signing key or order ledger."""
import json, pathlib, subprocess, tempfile, uuid
ROOT = pathlib.Path(__file__).resolve().parents[1]
def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True)
with tempfile.TemporaryDirectory() as temp:
    temp = pathlib.Path(temp)
    issuer = temp / 'issuer'
    run('xcrun', 'swiftc', '-module-cache-path', str(temp/'cache'), str(ROOT/'scripts/manual-license.swift'), '-o', str(issuer))
    private = temp / 'private'
    public = run(str(issuer), 'keygen', str(private)).stdout.strip()
    machine = str(uuid.uuid4()).upper()
    token = run(str(issuer), 'issue', str(private), 'fixture-order', machine, '29').stdout.strip()
    assert token == run(str(issuer), 'issue', str(private), 'fixture-order', machine, '29').stdout.strip()
    check_source = temp/'Check.swift'
    check_source.write_text('''import Foundation
@main struct Check { static func main() {
let a = CommandLine.arguments
precondition(ManualLicense.verify(a[1], publicKey: a[2], installation: a[3]))
precondition(!ManualLicense.verify(a[1], publicKey: a[2], installation: UUID().uuidString))
print("PASS: seller signature verified by app verifier")
}}''')
    verifier = temp/'verifier'
    run('xcrun','swiftc','-module-cache-path',str(temp/'cache'),str(ROOT/'source/ManualLicense.swift'),str(check_source),'-o',str(verifier))
    run(str(verifier),token,public,machine)
    for _ in range(2):
        run(str(issuer), 'issue', str(private), 'fixture-order', str(uuid.uuid4()), '29')
    rejected = subprocess.run([str(issuer), 'issue', str(private), 'fixture-order', str(uuid.uuid4()), '29'], capture_output=True)
    assert rejected.returncode != 0
    ledger = private/'orders.json'
    ledger.write_text(json.dumps({str(i): {'price':'29'} for i in range(50)}))
    rejected = subprocess.run([str(issuer), 'issue', str(private), 'new', str(uuid.uuid4()), '29'], capture_output=True)
    assert rejected.returncode != 0
    run(str(issuer), 'issue', str(private), 'new', str(uuid.uuid4()), '49')
    assert (private/'signing-private.key').stat().st_mode & 0o777 == 0o600
print('PASS: issuer signature, idempotency, three-device cap, fifty-discount cap, regular price and key permissions')
