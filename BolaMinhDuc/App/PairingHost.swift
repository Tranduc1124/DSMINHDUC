import Foundation
import Darwin

/// On-device pairing: finds the device's own `_remotepairing._tcp` service via
/// Bonjour (this also triggers the Local Network permission prompt), probes all
/// plausible addresses (Bonjour result, every 10.7.x interface, 10.7.0.1,
/// 127.0.0.1) with a raw TCP connect, then runs `tunnel_create_rppairing`
/// against the first reachable one with a freshly generated pairing file.
/// If the device shows a pairing code, the pin callback asks the UI for it.
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

    // MARK: interfaces + TCP probe

    /// All UP IPv4 interfaces as (name, address) pairs.
    static func ipv4Interfaces() -> [(String, String)] {
        var out: [(String, String)] = []
        var addrs: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&addrs) == 0, let first = addrs else { return out }
        defer { freeifaddrs(addrs) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            let name = String(cString: cur.pointee.ifa_name)
            if (flags & IFF_UP) != 0, let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                var sin = sockaddr_in()
                memcpy(&sin, sa, MemoryLayout<sockaddr_in>.size)
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var a = sin.sin_addr
                inet_ntop(AF_INET, &a, &buf, socklen_t(INET_ADDRSTRLEN))
                out.append((name, String(cString: buf)))
            }
            ptr = cur.pointee.ifa_next
        }
        return out
    }

    /// Heuristic: LocalDevVPN uses 10.7.0.1; accept any 10.7.x address or any
    /// active utun interface with an IPv4 address as "a tunnel is up".
    static func vpnLoopbackPresent() -> Bool {
        for (name, ip) in ipv4Interfaces() {
            if ip.hasPrefix("10.7.") {
                return true
            }
            if name.hasPrefix("utun") && !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") {
                return true
            }
        }
        return false
    }

    /// Raw non-blocking TCP connect probe; returns (connected, errno when not).
    static func probe(ip: String, port: UInt16, timeout: TimeInterval = 1.5) -> (Bool, Int32) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return (false, errno) }
        defer { close(fd) }
        let fl = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, fl | O_NONBLOCK)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard ip.withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else {
            return (false, EINVAL)
        }
        let r = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if r == 0 { return (true, 0) }
        if errno != EINPROGRESS { return (false, errno) }
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let pr = poll(&pfd, 1, Int32(timeout * 1000))
        if pr == 0 { return (false, ETIMEDOUT) }
        if pr < 0 { return (false, errno) }
        var soErr: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &soErr, &len)
        if soErr != 0 { return (false, soErr) }
        return (true, 0)
    }

    static func errName(_ code: Int32) -> String {
        let s = String(cString: strerror(code))
        return "lỗi \(code) (\(s))"
    }

    // MARK: generate

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
        let discovered = RPBrowser().discover(timeout: 6)
        if let d = discovered {
            progress("thấy dịch vụ tại \(d.0):\(d.1)")
        } else {
            progress("không thấy Bonjour")
        }

        let ifaces = ipv4Interfaces()
        var cands: [(String, UInt16)] = []
        if let d = discovered, !d.0.contains(":") {
            cands.append((d.0, UInt16(d.1)))
        }
        for (_, ip) in ifaces where ip.hasPrefix("10.7.") {
            cands.append((ip, 49152))
        }
        cands.append(("10.7.0.1", 49152))
        cands.append(("127.0.0.1", 49152))
        var seen = Set<String>()
        cands = cands.filter { seen.insert("\($0.0):\($0.1)").inserted }

        var chosen: (String, UInt16)? = nil
        var fails: [String] = []
        for c in cands {
            let (ok, e) = probe(ip: c.0, port: c.1)
            if ok {
                progress("kết nối được \(c.0):\(c.1)")
                chosen = c
                break
            } else {
                let es = errName(e)
                progress("không kết nối được \(c.0):\(c.1) — \(es)")
                fails.append("\(c.0):\(c.1) = \(es)")
            }
        }

        guard let (targetIP, targetPort) = chosen else {
            let ifDesc = ifaces.prefix(4).map { "\($0.0)=\($0.1)" }.joined(separator: ", ")
            let msg = "không kết nối được server ghép đôi.\nMạng: \(ifDesc.isEmpty ? "không thấy mạng" : ifDesc)\nThử: \(fails.joined(separator: "; "))"
            return .failure(PairError(message: msg))
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = targetPort.bigEndian
        let parseResult = targetIP.withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }
        guard parseResult == 1 else {
            return .failure(PairError(message: "địa chỉ không hợp lệ (\(targetIP))"))
        }

        progress("ghép đôi qua \(targetIP):\(targetPort)…")

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
            return .failure(PairError(message: "lỗi ghép đôi (code \(code)/\(sub)) tại \(targetIP):\(targetPort): \(text)"))
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
