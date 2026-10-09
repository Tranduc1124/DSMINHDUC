import Foundation
import Darwin

/// On-device pairing via the vendored idevice FFI (pairable-host flow).
/// Needs LocalDevVPN (the device reaches the host via the 10.7.0.1 loopback).
enum PairingHost {

    final class PinBox {
        var onPin: ((String) -> Void)?
    }

    final class StateBox {
        var cancel: OpaquePointer?
        var timedOut = false
    }

    private static let state = StateBox()

    private static let pinCallback: PairableHostPinCb = { pin, context in
        guard let pin = pin, let context = context else { return }
        let box = Unmanaged<PinBox>.fromOpaque(context).takeUnretainedValue()
        let code = String(cString: pin)
        if let cb = box.onPin {
            DispatchQueue.main.async { cb(code) }
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

    /// Stops a pending attempt (unblocks the FFI accept call).
    static func cancel() {
        if let c = state.cancel {
            pairable_host_cancel_signal(c)
        }
    }

    static func generate(progress: @escaping (String) -> Void,
                         onPin: @escaping (String) -> Void) -> Result<String, PairError> {
        let box = PinBox()
        box.onPin = onPin
        let ctx = Unmanaged.passUnretained(box).toOpaque()

        // Cancellation token, kept alive for the process lifetime: freeing it
        // while the watchdog may still fire would risk a use-after-free.
        let cancel = pairable_host_cancel_new()
        state.cancel = cancel
        state.timedOut = false

        DispatchQueue.global().asyncAfter(deadline: .now() + 120) {
            if let c = state.cancel {
                state.timedOut = true
                pairable_host_cancel_signal(c)
            }
        }

        var peer: UnsafeMutablePointer<RpPairingPeerDeviceC>? = nil
        var file: OpaquePointer? = nil

        progress("đang chờ máy kết nối — nhớ bật LocalDevVPN…")

        let err: UnsafeMutablePointer<IdeviceFfiError>? = withExtendedLifetime(box) {
            pairable_host_accept_with_options(
                "BolaMinhDuc",
                "Mac17,7",
                0,
                false,
                pinCallback,
                ctx,
                cancel,
                nil,
                &peer,
                &file
            )
        }

        defer {
            state.cancel = nil
            if let file = file {
                rp_pairing_file_free(file)
            }
            if let peer = peer {
                rppairing_peer_device_free(peer)
            }
        }

        if let err = err {
            let text = errorText(err)
            if state.timedOut {
                return .failure(PairError(message: "không thấy máy kết nối — kiểm tra LocalDevVPN + quyền Mạng cục bộ rồi thử lại"))
            }
            if text.lowercased().contains("cancel") {
                return .failure(PairError(message: "đã huỷ ghép đôi"))
            }
            return .failure(PairError(message: text))
        }
        guard let file = file else {
            return .failure(PairError(message: "ghép đôi xong nhưng không nhận được file"))
        }

        var data: UnsafeMutablePointer<UInt8>? = nil
        var len: UInt = 0
        let conv = rp_pairing_file_to_bytes(file, &data, &len)
        if let conv = conv {
            return .failure(PairError(message: errorText(conv)))
        }
        guard let data = data else {
            return .failure(PairError(message: "không đọc được file ghép đôi"))
        }
        defer { idevice_data_free(data, len) }

        let bytes = Data(bytes: data, count: Int(len))
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("bola_pairing.mobiledevicepairing")
        do {
            try bytes.write(to: url, options: .atomic)
        } catch {
            return .failure(PairError(message: "không ghi được file: \(error.localizedDescription)"))
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
