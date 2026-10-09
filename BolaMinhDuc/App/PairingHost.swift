import Foundation
import Darwin

/// On-device pairing: connects to the device's own `_remotepairing` service
/// through the LocalDevVPN loopback (10.7.0.1:49152), runs pair-setup with a
/// freshly generated pairing file and saves it. No computer required.
enum PairingHost {

    // MARK: pin relay (the device shows a code; the user types it in-app)

    final class PinEntryBox {
        let sem = DispatchSemaphore(value: 0)
        var pin: String?
    }

    private static let pinEntry = PinEntryBox()
    private static let pinBuf: UnsafeMutablePointer<CChar> = {
        let p = UnsafeMutablePointer<CChar>.allocate(capacity: 16)
        p.initialize(repeating: 0, count: 16)
        return p
    }()

    static var onNeedPin: (() -> Void)?

    private static let pinEntryCallback: @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>? = { _ in
        if let onNeed = PairingHost.onNeedPin {
            DispatchQueue.main.async { onNeed() }
        }
        pinEntry.sem.wait()
        let code = pinEntry.pin ?? ""
        pinEntry.pin = nil
        let utf8 = Array(code.utf8.prefix(15))
        for i in 0..<16 {
            pinBuf[i] = 0
        }
        for (i, b) in utf8.enumerated() {
            pinBuf[i] = CChar(bitPattern: b)
        }
        return UnsafePointer(pinBuf)
    }

    /// Called from the UI with the code shown on the device screen.
    static func submitPin(_ pin: String) {
        pinEntry.pin = pin
        pinEntry.sem.signal()
    }

    /// Fallback escape: unblocks a waiting pin prompt (empty code → pairing fails).
    static func cancel() {
        pinEntry.pin = ""
        pinEntry.sem.signal()
    }

    /// Heuristic: LocalDevVPN uses 10.7.0.1; accept any 10.7.x address or any
    /// active utun interface with an IPv4 address as "a tunnel is up".
    static func vpnLoopbackPresent() -> Bool {
        var addrs: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&addrs) == 0, let first = addrs else { return false }
        defer { freeifaddrs(addrs) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            let name = String(cString: cur.pointee.ifa_name)
            if (flags & IFF_UP) != 0, let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                var sin = sockaddr_in()
                memcpy(&sin, sa, MemoryLayout<sockaddr_in>.size)
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var addr = sin.sin_addr
                inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN))
                let ip = String(cString: buf)
                if ip.hasPrefix("10.7.") {
                    return true
                }
                if name.hasPrefix("utun") && !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") {
                    return true
                }
            }
            ptr = cur.pointee.ifa_next
        }
        return false
    }

    static func generate(progress: @escaping (String) -> Void) -> Result<String, PairError> {
        var file: OpaquePointer? = nil
        let genErr = rp_pairing_file_generate("BolaMinhDuc", &file)
        if let genErr = genErr {
            return .failure(PairError(message: errorText(genErr)))
        }
        guard let pairFile = file else {
            return .failure(PairError(message: "không tạo được pairing file"))
        }
        defer { rp_pairing_file_free(pairFile) }

        progress("kết nối 10.7.0.1:49152 (cần LocalDevVPN)…")

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(49152).bigEndian
        addr.sin_addr.s_addr = inet_addr("10.7.0.1")

        var adapter: OpaquePointer? = nil
        var handshake: OpaquePointer? = nil

        let err: UnsafeMutablePointer<IdeviceFfiError>? = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                tunnel_create_rppairing(
                    sa,
                    socklen_t(MemoryLayout<sockaddr_in>.size),
                    "BolaMinhDuc",
                    pairFile,
                    pinEntryCallback,
                    nil,
                    &adapter,
                    &handshake
                )
            }
        }

        defer {
            if let handshake = handshake {
                rsd_handshake_free(handshake)
            }
            if let adapter = adapter {
                adapter_free(adapter)
            }
        }

        if let err = err {
            let text = errorText(err)
            let lower = text.lowercased()
            if lower.contains("connect") || lower.contains("refused") || lower.contains("timed out") || lower.contains("unreachable") {
                return .failure(PairError(message: "không kết nối được 10.7.0.1:49152 — kiểm tra LocalDevVPN đã bật"))
            }
            return .failure(PairError(message: text))
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("bola_pairing.mobiledevicepairing")
        let writeErr = rp_pairing_file_write(pairFile, url.path)
        if let writeErr = writeErr {
            return .failure(PairError(message: errorText(writeErr)))
        }
        progress("đã lưu file ghép đôi")
        return .success("bola_pairing.mobiledevicepairing")
    }

    private static func errorText(_ err: UnsafeMutablePointer<IdeviceFfiError>) -> String {
        let e = err.pointee
        var text = "lỗi \(e.code)"
        if let msg = e.message {
            text = String(cString: msg)
        }
        idevice_error_free(err)
        return text
    }
}
