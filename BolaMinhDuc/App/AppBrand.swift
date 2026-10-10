import Foundation

/// Thương hiệu theo từng target build (BOLAMINHDUC / IntexX).
/// Lấy từ Info.plist (CFBundleDisplayName + BolaProduct) nên mỗi bản tự
/// hiển thị đúng tên + biểu tượng của mình trong TOÀN BỘ giao diện.
enum AppBrand {
    /// Tên hiển thị (BOLAMINHDUC / IntexX).
    static var name: String {
        let v = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? ""
        let s = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "BOLAMINHDUC" : s
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

    /// Link Group Telegram (theo target — Info.plist "BolaTelegram"; rỗng = ẩn).
    static var telegramURL: String {
        let v = (Bundle.main.object(forInfoDictionaryKey: "BolaTelegram") as? String) ?? ""
        return v.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
