import Foundation

/// Thương hiệu theo target — tên + Tele XOR-encode trong binary,
/// KHÔNG đọc CFBundleDisplayName / BolaTelegram từ Info.plist
/// (cracker sửa plist không đổi được menu / link trong app).
enum AppBrand {
    private static let xorKey: UInt8 = 0x5A

    /// Tên hiển thị (MinDo Cheat / IntexX) — decode runtime.
    static var name: String {
        isIntexX ? decode([19, 52, 46, 63, 34, 2])
                 : decode([23, 51, 52, 30, 53, 122, 25, 50, 63, 59, 46])
    }

    /// Bản này có phải IntexX không.
    static var isIntexX: Bool {
        let v = (Bundle.main.object(forInfoDictionaryKey: "BolaProduct") as? String) ?? "bola"
        return v.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "intexx"
    }

    /// Biểu tượng nhỏ trong header (đổi theo bản).
    static var symbol: String {
        return isIntexX ? "crown.fill" : "bolt.shield.fill"
    }

    /// Link Group Telegram — decode runtime; rỗng = ẩn card.
    static var telegramURL: String {
        isIntexX
            ? decode([50, 46, 46, 42, 41, 96, 117, 117, 46, 116, 55, 63, 117, 51, 52, 46, 63, 34, 34, 57, 50, 63, 59, 46])
            : decode([50, 46, 46, 42, 41, 96, 117, 117, 46, 116, 55, 63, 117, 52, 46, 42, 50, 59, 34])
    }

    private static func decode(_ bytes: [UInt8]) -> String {
        String(bytes: bytes.map { $0 ^ xorKey }, encoding: .utf8) ?? ""
    }
}
