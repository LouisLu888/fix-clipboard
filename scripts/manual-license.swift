// Seller-only CLI. Private keys and order records must live outside the repository.
import Foundation
import CryptoKit
import Darwin

func fail(_ text: String) -> Never { fputs(text + "\n", stderr); exit(1) }
let args = CommandLine.arguments
// keygen <private-directory> | issue <private-directory> <order-id> <installation-uuid> <29|49>
guard args.count >= 3 else { fail("Usage: keygen DIR | issue DIR ORDER INSTALLATION_UUID 29|49") }
let directory = URL(fileURLWithPath: args[2], isDirectory: true)
umask(0o077)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
let keyURL = directory.appendingPathComponent("signing-private.key")
let lockPath = directory.appendingPathComponent("issuer.lock").path
let fd = open(lockPath, O_CREAT | O_RDWR, 0o600)
guard fd >= 0, flock(fd, LOCK_EX) == 0 else { fail("Cannot lock issuer directory") }
defer { flock(fd, LOCK_UN); close(fd) }
if args[1] == "keygen" {
    guard !FileManager.default.fileExists(atPath: keyURL.path) else { fail("Key already exists; refusing to replace it") }
    let key = Curve25519.Signing.PrivateKey()
    try key.rawRepresentation.write(to: keyURL, options: .withoutOverwriting)
    print(key.publicKey.rawRepresentation.base64EncodedString())
} else if args[1] == "issue" {
    guard args.count == 6, let installation = UUID(uuidString: args[4]), ["29", "49"].contains(args[5]),
          !args[3].isEmpty, args[3].count <= 80 else { fail("Provide ORDER INSTALLATION_UUID 29|49 after verifying payment") }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyURL))
    let ledgerURL = directory.appendingPathComponent("orders.json")
    var ledger: [String: [String: String]] = [:]
    if FileManager.default.fileExists(atPath: ledgerURL.path) {
        ledger = try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: ledgerURL))
    }
    let order = args[3]; let id = installation.uuidString
    if let existing = ledger[order]?[id] { print(existing); exit(0) }
    var devices = ledger[order] ?? [:]
    guard devices.filter({ $0.key != "price" }).count < 3 else { fail("Order already has 3 installations. Offline keys cannot be remotely revoked.") }
    if let price = devices["price"], price != args[5] { fail("Order price does not match the ledger") }
    if ledger[order] == nil && args[5] == "29" && ledger.count >= 50 {
        fail("The first 50 discounted orders have been issued; use 49 for new orders")
    }
    let payload: [String: Any] = ["version": 1, "product": "fix-clipboard-pro-v1", "order": order, "installation": id]
    let data = try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys)
    let token = "FC1." + data.base64EncodedString() + "." + (try key.signature(for: data)).base64EncodedString()
    devices[id] = token; devices["price"] = args[5]; ledger[order] = devices
    try JSONEncoder().encode(ledger).write(to: ledgerURL, options: .atomic)
    print(token)
} else { fail("Unknown command") }
