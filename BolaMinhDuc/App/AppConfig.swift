import Foundation

/// Build switches.
enum AppConfig {
    /// Có bắt buộc dùng key TserVer không.
    ///
    /// - MinDo  (`BolaProduct = bola`)   : KHÔNG dùng key — mở thẳng vào app.
    /// - IntexX (`BolaProduct = intexx`) : vẫn dùng key (bản đại lí).
    ///
    /// Muốn bật key lại cho MinDo: thêm `case "bola": return true` bên dưới.
    static let requireKey: Bool = {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "BolaProduct") as? String) ?? "bola"
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "intexx":
            return true
        default:
            return false
        }
    }()

    /// "Key" giả cho bản keyless — để các đoạn code cũ (trailer patch, key bar,
    /// log) vẫn chạy mà không cần license thật.
    static let keylessKey = "MINDO-APP"
}
