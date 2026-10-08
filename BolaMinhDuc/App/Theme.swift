import SwiftUI
import Foundation
import Darwin

/// BOLAMINHDUC monochrome theme: near-black surfaces, white accents,
/// white primary button with black label (Delta-style).
enum Theme {
    static let bg = Color(red: 0.035, green: 0.035, blue: 0.04)
    static let bgTop = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let card = Color(red: 0.075, green: 0.075, blue: 0.082)
    static let cardHi = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let border = Color.white.opacity(0.08)
    static let borderHi = Color.white.opacity(0.16)
    static let dim = Color(white: 0.58)
    static let dimmer = Color(white: 0.42)

    static var background: some View {
        LinearGradient(colors: [bgTop, bg, bg],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

/// Primary action button: white fill, black text.
struct WhiteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.black)
            .background(Color.white.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Secondary: dark surface, white text, thin border.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .background(Theme.cardHi.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.borderHi, lineWidth: 1)
            )
    }
}

enum DeviceInfo {
    static var machine: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let mirror = Mirror(reflecting: sysinfo.machine)
        let id = mirror.children.compactMap { $0.value as? Int8 }
            .filter { $0 != 0 }
            .map { String(UnicodeScalar(UInt8($0))) }
            .joined()
        if id.hasPrefix("iPhone") || id.hasPrefix("iPad") {
            return friendlyName(id)
        }
        return id.isEmpty ? "iPhone" : id
    }

    private static func friendlyName(_ id: String) -> String {
        // just show the raw model identifier; it is what jailbreak tools use
        id
    }

    static var iosVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(short)"
    }
}
