import Foundation
import Darwin

/// On-device pairing: finds the device's own `_remotepairing._tcp` service via
/// Bonjour (this also triggers the Local Network permission prompt), then runs
/// `tunnel_create_rppairing` against the discovered address with a freshly
/// generated pairing file. Falls back to 10.7.0.1:49152 (LocalDevVPN) if the
/// Bonjour browse finds nothing. If the device shows a pairing code, the pin
/// callback asks the UI for it (pin relay).
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

    // MARK: Bonjour discovery of the device's own remotepairing service

    final class RPBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
        private var resolved: [(String, Int)] = []
        private var browser: NetServiceBrowser?

        /// Runs the browse on a dedicated thread with its own run loop
        /// (generate() is called from a background queue without one).
        func discover(timeout: TimeInterval) -> (String, Int)? {
            var out: (String, Int)? = nil
            let done = DispatchSemaphore(value: 0)
            let t = Thread { [weak self] in
                guard let self = self else { done.signal(); return }
                let b = NetServiceBrowser()
                b.delegate = self
                b.searchForServices(ofType: "_remotepairing._tcp.", inDomain: "local.")
                self.browser = b
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.25))
                    if self.resolved.contains(where: { $0.0.hasPrefix("10.7.") }) { break }
                }
                b.stop()
                out = self.best()
                done.signal()
            }
            t.start()
            _ = done.wait(timeout: .now() + timeout + 4)
            return out
        }

        private func best() -> (String, Int)? {
            if let v = resolved.first(where: { $0.0.hasPrefix("10.7.") }) {
                return v
            }
            return resolved.first
        }

        func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
            service.delegate = self
            service.resolve(withTimeout: 5)
        }

        func netServiceDidResolveAddress(_ sender: NetService) {
            let port = sender.port
            guard port > 0, port < 65536 else { return }
            if let addresses = sender.addresses {
                for data in addresses {
                    if let ip = RPBrowser.ipString(from: data) {
                        if !resolved.contains(where: { $0.0 == ip && $0.1 == port }) {
                            resolved.append((ip, port))
                        }
                        return
                    }
                }
            }
        }

        func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
            // ignore; we keep waiting for other services until timeout
        }

        static func ipString(from data: Data) -> String? {
            var storage = sockaddr_storage()
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress, raw.count <= MemoryLayout<sockaddr_storage>.size else { return }
                memcpy(&storage, base, raw.count)
            }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = storage.ss_family == sa_family_t(AF_INET6)
                ? socklen_t(MemoryLayout<sockaddr_in6>.size)
                : socklen_t(MemoryLayout<sockaddr_in>.size)
            let res = withUnsafePointer(to: &storage) { p in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    getnameinfo(sa, len, &host, socklen_t(NI_MAXHOST), nil, 0, NI_NUMERICHOST)
                }
            }
            guard res == 0 else { return nil }
            let ip = String(cString: host)
            if ip.hasPrefix("fe80:") { return nil }
            return ip
        }
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

        progress("đang tìm dịch vụ ghép đôi (Bonjour)…")
        var targetIP = "10.7.0.1"
        var targetPort: UInt16 = 49152
        if let found = RPBrowser().discover(timeout: 6) {
            targetIP = found.0
            if found.1 > 0 && found.1 < 65536 {
                targetPort = UInt16(found.1)
            }
            progress("thấy dịch vụ tại \(targetIP):\(targetPort)")
        } else {
            progress("không thấy Bonjour — thử mặc định 10.7.0.1:49152")
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = targetPort.bigEndian
        let parseResult = targetIP.withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }
        guard parseResult == 1 else {
            return .failure(PairError(message: "địa chỉ không hợp lệ (\(targetIP))"))
        }

        progress("kết nối \(targetIP):\(targetPort)…")

        var adapter: OpaquePointer? = nil
        var handshake: OpaquePointer? = nil

        let err: UnsafeMutablePointer<IdeviceFfiError>? = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                tunnel_create_rppairing(
                    sa,
                    socklen_t(MemoryLayout<sockaddr_in>.stride),
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
            let code = err.pointee.code
            let sub = err.pointee.sub_code
            let text = errorText(err)
            return .failure(PairError(message: "lỗi ghép đôi (code \(code)/\(sub)): \(text)"))
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
        var text = "không có mô tả"
        if let msg = e.message {
            text = String(cString: msg)
        }
        idevice_error_free(err)
        return text
    }
}
