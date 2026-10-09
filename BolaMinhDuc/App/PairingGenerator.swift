import Foundation
import Security
import CryptoKit
import Darwin

/// On-device iOS pairing-file generator (Jitterbug-style, via usbmuxd loopback).
/// Mirrors pymobiledevice3's classic Pair flow:
///   GetValue("") -> build root/host/device cert chain (validated DER encoder)
///   -> Pair request (device shows the Trust dialog) -> save the pairing record.
/// No computer required.
enum PairingGenerator {

    static func generate(progress: @escaping (String) -> Void) -> Result<String, PairError> {
        do {
            return .success(try generateThrowing(progress: progress))
        } catch let e as PairError {
            return .failure(e)
        } catch {
            return .failure(PairError(message: "lỗi không xác định: \(error.localizedDescription)"))
        }
    }

    // MARK: - flow

    private static func generateThrowing(progress: @escaping (String) -> Void) throws -> String {
        progress("kết nối usbmuxd…")
        let sock = try SocketClient(host: "127.0.0.1", port: 27015)
        defer { sock.close() }

        try sock.sendMuxConnect(port: 62078, tag: 1)
        let (rtype, rplist) = try sock.recvMux()
        guard rtype == 1 else { throw PairError(message: "usbmuxd từ chối kết nối") }
        if let num = rplist["Number"] as? Int, num != 0 {
            throw PairError(message: "không mở được lockdownd (mã \(num))")
        }

        progress("đọc khóa thiết bị…")
        var values: [String: Any] = [:]
        let vresp = try sock.ldRequest(["Label": "BolaMinhDuc", "Request": "GetValue", "Domain": ""])
        if let v = vresp["Value"] as? [String: Any] { values = v }
        var devKeyPEM = values["DevicePublicKey"] as? String
        if devKeyPEM == nil || devKeyPEM!.isEmpty {
            let kresp = try sock.ldRequest(["Label": "BolaMinhDuc", "Request": "GetValue", "Domain": "", "Key": "DevicePublicKey"])
            devKeyPEM = kresp["Value"] as? String
        }
        guard let pem = devKeyPEM, !pem.isEmpty, let devKeyDER = PairingPEM.derFromPEM(pem) else {
            throw PairError(message: "không lấy được khóa thiết bị — chạy lại thử nhé")
        }

        let udid = (values["UniqueDeviceID"] as? String) ?? "device"
        let wifiMac = (values["WiFiAddress"] as? String) ?? "00:00:00:00:00:00"
        let buid = (values["SystemBUID"] as? String) ?? ""

        progress("tạo chứng chỉ (RSA 2048)…")
        let chain = try PairingCertChain(devicePublicKeyPKCS1: devKeyDER)

        let hostID = UUID().uuidString.replacingOccurrences(of: "-", with: "")

        var pairRecord: [String: Any] = [
            "DeviceCertificate": chain.deviceCertPEM,
            "HostCertificate": chain.hostCertPEM,
            "HostID": hostID,
            "RootCertificate": chain.rootCertPEM,
            "RootPrivateKey": chain.rootKeyPEM,
            "WiFiMACAddress": wifiMac,
            "SystemBUID": buid
        ]

        let pairRequest: [String: Any] = [
            "Label": "BolaMinhDuc",
            "Request": "Pair",
            "HostName": "BolaMinhDuc",
            "PairRecord": pairRecord,
            "ProtocolVersion": "2",
            "PairingOptions": ["ExtendedPairingErrors": true]
        ]

        progress("gửi yêu cầu ghép đôi — bấm Tin cậy trên màn hình khi máy hỏi…")
        let deadline = Date().addingTimeInterval(170)
        var response: [String: Any] = [:]
        while true {
            response = try sock.ldRequest(pairRequest)
            if let err = response["Error"] as? String, err == "PairingDialogResponsePending" {
                if Date() > deadline {
                    throw PairError(message: "chưa thấy bấm Tin cậy — thử lại nhé")
                }
                progress("đang chờ bạn bấm Tin cậy…")
                Thread.sleep(forTimeInterval: 2)
                continue
            }
            break
        }

        if let err = response["Error"] as? String {
            if err.lowercased().contains("denied") {
                throw PairError(message: "bạn đã từ chối ghép đôi trên máy")
            }
            throw PairError(message: "ghép đôi lỗi: \(err)")
        }

        pairRecord["HostPrivateKey"] = chain.hostKeyPEM
        if let bag = response["EscrowBag"] {
            pairRecord["EscrowBag"] = bag
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "bola_pairing.mobiledevicepairing"
        let url = docs.appendingPathComponent(fileName)
        let data = try PropertyListSerialization.data(fromPropertyList: pairRecord, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
        progress("đã lưu \(fileName) — UDID \(udid)")
        return fileName
    }
}

// MARK: - errors

struct PairError: Error {
    let message: String
}

// MARK: - POSIX socket client (usbmuxd + lockdown framing)

final class SocketClient {
    private var fd: Int32 = -1

    init(host: String, port: UInt16) throws {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw PairError(message: "không tạo được socket") }
        var tv = timeval(tv_sec: 180, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(host)
        let res = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard res == 0 else {
            Darwin.close(fd)
            fd = -1
            throw PairError(message: "không kết nối được usbmuxd — thiết bị chặn loopback?")
        }
    }

    func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    func send(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var off = 0
            while off < data.count {
                let n = Darwin.send(fd, base + off, data.count - off, 0)
                if n <= 0 { throw PairError(message: "gửi thất bại") }
                off += n
            }
        }
    }

    func recvExact(_ count: Int) throws -> Data {
        var out = Data(capacity: count)
        var buf = [UInt8](repeating: 0, count: 65536)
        while out.count < count {
            let want = min(65536, count - out.count)
            let n = buf.withUnsafeMutableBytes { raw in
                Darwin.recv(fd, raw.baseAddress, want, 0)
            }
            if n <= 0 { throw PairError(message: "mất kết nối/timeout với usbmuxd") }
            out.append(contentsOf: buf[0..<n])
        }
        return out
    }

    // MARK: usbmuxd

    func sendMuxConnect(port: UInt16, tag: UInt32) throws {
        let plist: [String: Any] = ["MessageType": "Connect", "PortNumber": Int(port)]
        let body = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        var d = Data()
        d.appendLE32(UInt32(16 + body.count))
        d.appendLE32(1)
        d.appendLE32(8)
        d.appendLE32(tag)
        d.append(body)
        try send(d)
    }

    func recvMux() throws -> (UInt32, [String: Any]) {
        let header = try recvExact(16)
        let total = header.le32(0)
        let type = header.le32(8)
        var body = Data()
        if total > 16 { body = try recvExact(Int(total) - 16) }
        let plist = ((try? PropertyListSerialization.propertyList(from: body, options: [], format: nil)) as? [String: Any]) ?? [:]
        return (type, plist)
    }

    // MARK: lockdown

    func ldRequest(_ dict: [String: Any]) throws -> [String: Any] {
        let body = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        var d = Data()
        let n = UInt32(body.count)
        d.append(UInt8((n >> 24) & 0xFF))
        d.append(UInt8((n >> 16) & 0xFF))
        d.append(UInt8((n >> 8) & 0xFF))
        d.append(UInt8(n & 0xFF))
        d.append(body)
        try send(d)
        return try ldRecv()
    }

    func ldRecv() throws -> [String: Any] {
        let lenData = try recvExact(4)
        let n = (UInt32(lenData[lenData.startIndex]) << 24)
            | (UInt32(lenData[lenData.startIndex + 1]) << 16)
            | (UInt32(lenData[lenData.startIndex + 2]) << 8)
            | UInt32(lenData[lenData.startIndex + 3])
        guard n > 0 && n < 8_000_000 else { throw PairError(message: "phản hồi lockdown lỗi") }
        let body = try recvExact(Int(n))
        guard let plist = ((try? PropertyListSerialization.propertyList(from: body, options: [], format: nil)) as? [String: Any]) else {
            throw PairError(message: "plist lockdown lỗi")
        }
        return plist
    }
}

extension Data {
    mutating func appendLE32(_ v: UInt32) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 24) & 0xFF))
    }

    func le32(_ off: Int) -> UInt32 {
        let i = startIndex + off
        return UInt32(self[i])
            | (UInt32(self[i + 1]) << 8)
            | (UInt32(self[i + 2]) << 16)
            | (UInt32(self[i + 3]) << 24)
    }
}

// MARK: - minimal DER encoder (validated against openssl + pymobiledevice3 ca.py)

enum DER {
    static func length(_ n: Int) -> Data {
        if n < 0x80 { return Data([UInt8(n)]) }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        var d = Data([tag])
        d.append(length(content.count))
        d.append(content)
        return d
    }

    static func seq(_ items: [Data]) -> Data {
        var c = Data()
        for i in items { c.append(i) }
        return tlv(0x30, c)
    }

    static func oid(_ bytes: [UInt8]) -> Data { tlv(0x06, Data(bytes)) }

    static func integer(_ value: Int) -> Data {
        var out: [UInt8] = []
        var x = value
        repeat {
            out.insert(UInt8(x & 0xFF), at: 0)
            x >>= 8
        } while x > 0
        if out[0] & 0x80 != 0 { out.insert(0, at: 0) }
        return tlv(0x02, Data(out))
    }

    static func null() -> Data { Data([0x05, 0x00]) }

    static func bitString(_ content: Data, unusedBits: UInt8) -> Data {
        var c = Data([unusedBits])
        c.append(content)
        return tlv(0x03, c)
    }

    static func octetString(_ content: Data) -> Data { tlv(0x04, content) }

    static func boolean(_ value: Bool) -> Data { Data([0x01, 0x01, value ? 0xFF : 0x00]) }

    static func utcTime(_ date: Date) -> Data {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyMMddHHmmss"
        return tlv(0x17, Data((f.string(from: date) + "Z").utf8))
    }

    static func context(_ n: UInt8, _ content: Data) -> Data { tlv(0xA0 | n, content) }
}

// MARK: - RSA keys (Security.framework)

struct PairingRSAKey {
    let secKey: SecKey
    let privatePKCS1: Data
    let publicPKCS1: Data

    static func generate() throws -> PairingRSAKey {
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var err: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(attrs as CFDictionary, &err) else {
            throw PairError(message: "không tạo được khóa RSA")
        }
        guard let pub = SecKeyCopyPublicKey(priv),
              let privDER = SecKeyCopyExternalRepresentation(priv, &err) as Data?,
              let pubDER = SecKeyCopyExternalRepresentation(pub, &err) as Data? else {
            throw PairError(message: "không xuất được khóa RSA")
        }
        return PairingRSAKey(secKey: priv, privatePKCS1: privDER, publicPKCS1: pubDER)
    }

    func signSHA256(_ data: Data) throws -> Data {
        var err: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(secKey, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, &err) as Data? else {
            throw PairError(message: "ký chứng chỉ thất bại")
        }
        return sig
    }
}

// MARK: - PEM helpers

enum PairingPEM {
    static func derFromPEM(_ pem: String) -> Data? {
        let lines = pem.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        return Data(base64Encoded: lines.joined())
    }
}

// MARK: - certificate chain (root -> host/device), mirrors pymobiledevice3 ca.py

struct PairingCertChain {
    let hostCertPEM: String
    let hostKeyPEM: String
    let deviceCertPEM: String
    let rootCertPEM: String
    let rootKeyPEM: String

    private static let rsaOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
    private static let sha256RSAOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]

    init(devicePublicKeyPKCS1: Data) throws {
        let sigAlg = DER.seq([DER.oid(Self.sha256RSAOID), DER.null()])
        let rootKey = try PairingRSAKey.generate()
        let hostKey = try PairingRSAKey.generate()

        let rootTBS = Self.tbs(publicKeyPKCS1: rootKey.publicPKCS1,
                               extensions: [Self.basicConstraints(ca: true)],
                               sigAlg: sigAlg)
        let rootSig = try rootKey.signSHA256(rootTBS)
        let rootCert = DER.seq([rootTBS, sigAlg, DER.bitString(rootSig, unusedBits: 0)])

        let hostTBS = Self.tbs(publicKeyPKCS1: hostKey.publicPKCS1,
                               extensions: [Self.basicConstraints(ca: false), Self.keyUsage()],
                               sigAlg: sigAlg)
        let hostSig = try rootKey.signSHA256(hostTBS)
        let hostCert = DER.seq([hostTBS, sigAlg, DER.bitString(hostSig, unusedBits: 0)])

        let devTBS = Self.tbs(publicKeyPKCS1: devicePublicKeyPKCS1,
                              extensions: [Self.basicConstraints(ca: false), Self.keyUsage(),
                                           Self.subjectKeyId(devicePublicKeyPKCS1)],
                              sigAlg: sigAlg)
        let devSig = try rootKey.signSHA256(devTBS)
        let devCert = DER.seq([devTBS, sigAlg, DER.bitString(devSig, unusedBits: 0)])

        hostCertPEM = Self.pem("CERTIFICATE", hostCert)
        deviceCertPEM = Self.pem("CERTIFICATE", devCert)
        rootCertPEM = Self.pem("CERTIFICATE", rootCert)
        hostKeyPEM = Self.pkcs8PEM(hostKey.privatePKCS1)
        rootKeyPEM = Self.pkcs8PEM(rootKey.privatePKCS1)
    }

    private static func tbs(publicKeyPKCS1: Data, extensions: [Data], sigAlg: Data) -> Data {
        let spki = DER.seq([
            DER.seq([DER.oid(rsaOID), DER.null()]),
            DER.bitString(publicKeyPKCS1, unusedBits: 0)
        ])
        let empty = DER.seq([])
        let now = Date()
        let nb = now.addingTimeInterval(-60)
        let na = now.addingTimeInterval(60 * 60 * 24 * 365 * 10)
        var parts: [Data] = []
        parts.append(DER.context(0, DER.integer(2)))
        parts.append(DER.integer(1))
        parts.append(sigAlg)
        parts.append(empty)
        parts.append(DER.seq([DER.utcTime(nb), DER.utcTime(na)]))
        parts.append(empty)
        parts.append(spki)
        if !extensions.isEmpty {
            parts.append(DER.context(3, DER.seq(extensions)))
        }
        return DER.seq(parts)
    }

    private static func extItem(_ oidBytes: [UInt8], critical: Bool, value: Data) -> Data {
        var parts: [Data] = [DER.oid(oidBytes)]
        if critical { parts.append(DER.boolean(true)) }
        parts.append(DER.octetString(value))
        return DER.seq(parts)
    }

    private static func basicConstraints(ca: Bool) -> Data {
        let value = ca ? DER.seq([DER.boolean(true)]) : DER.seq([])
        return extItem([0x55, 0x1D, 0x13], critical: true, value: value)
    }

    private static func keyUsage() -> Data {
        return extItem([0x55, 0x1D, 0x0F], critical: true, value: DER.bitString(Data([0xA0]), unusedBits: 5))
    }

    private static func subjectKeyId(_ pub: Data) -> Data {
        let digest = Data(Insecure.SHA1.hash(data: pub))
        return extItem([0x55, 0x1D, 0x0E], critical: false, value: DER.octetString(digest))
    }

    private static func pem(_ label: String, _ der: Data) -> String {
        let b64 = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN \(label)-----\n\(b64)\n-----END \(label)-----\n"
    }

    private static func pkcs8PEM(_ pkcs1: Data) -> String {
        let alg = DER.seq([DER.oid(rsaOID), DER.null()])
        let info = DER.seq([DER.integer(0), alg, DER.octetString(pkcs1)])
        return pem("PRIVATE KEY", info)
    }
}
