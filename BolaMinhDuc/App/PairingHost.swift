import Foundation

/// On-device pairing via the vendored idevice FFI (pairable-host flow).
/// Needs LocalDevVPN so the device can reach the advertised Bonjour service.
enum PairingHost {

    final class PinBox {
        var onPin: ((String) -> Void)?
    }

    private static let pinCallback: PairableHostPinCb = { pin, context in
        guard let pin = pin, let context = context else { return }
        let box = Unmanaged<PinBox>.fromOpaque(context).takeUnretainedValue()
        let code = String(cString: pin)
        if let cb = box.onPin {
            DispatchQueue.main.async { cb(code) }
        }
    }

    static func generate(progress: @escaping (String) -> Void,
                         onPin: @escaping (String) -> Void) -> Result<String, PairError> {
        let box = PinBox()
        box.onPin = onPin
        let ctx = Unmanaged.passUnretained(box).toOpaque()

        var peer: UnsafeMutablePointer<RpPairingPeerDeviceC>? = nil
        var file: OpaquePointer? = nil

        progress("bật LocalDevVPN rồi chờ máy kết nối…")

        let err: UnsafeMutablePointer<IdeviceFfiError>? = withExtendedLifetime(box) {
            pairable_host_accept_with_options(
                "BolaMinhDuc",
                "Mac17,7",
                0,
                false,
                pinCallback,
                ctx,
                nil,
                nil,
                &peer,
                &file
            )
        }

        defer {
            if let file = file {
                rp_pairing_file_free(file)
            }
            if let peer = peer {
                rppairing_peer_device_free(peer)
            }
        }

        if let err = err {
            return .failure(PairError(message: errorText(err)))
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
