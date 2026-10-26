import Foundation

/// Build switches (compile-time constants).
enum AppConfig {
    /// `true`  = bật lại hệ thống key TserVer (màn key + activate server).
    /// `false` = bản KHÔNG DÙNG KEY: mở app vào thẳng ContentView,
    ///           không gọi SDK, không gọi server license.
    ///
    /// Đổi sang `true` là có key lại, không cần sửa chỗ nào khác.
    static let requireKey = false

    /// "Key" giả cho bản keyless — để các đoạn code cũ (trailer patch, key bar,
    /// log) vẫn chạy mà không cần license thật.
    static let keylessKey = "MINDO-APP"
}
