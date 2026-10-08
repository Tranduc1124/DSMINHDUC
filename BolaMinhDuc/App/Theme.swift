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

/// pulsing status dot (soft breathing animation)
struct StatusDot: View {
    var color: Color
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .scaleEffect(on ? 1.35 : 0.9)
            .opacity(on ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// in-app toast (custom popup, replaces the system alert)
struct ToastView: View {
    let message: String
    var close: () -> Void = {}

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundColor(.white)
                .lineLimit(5)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.cardHi)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.borderHi, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        .onTapGesture { close() }
    }
}

/// card press effect for tappable rows
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// full-width row press highlight (settings rows)
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.05) : Color.clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// slides a custom toast in from the top whenever the binding is set
    func toastOverlay(_ text: Binding<String?>) -> some View {
        self.overlay(alignment: .top) {
            if let msg = text.wrappedValue {
                ToastView(message: msg, close: { text.wrappedValue = nil })
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: text.wrappedValue)
    }
}
