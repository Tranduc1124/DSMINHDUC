import SwiftUI

/// CÀI ĐẶT — Delta-style sheet: big header, rounded rows card, language picker.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    var openLanguage: () -> Void

    @State private var appear = false

    var body: some View {
        ZStack {
            Theme.background
            Circle()
                .fill(Color.white.opacity(0.045))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(y: -190)
                .allowsHitTesting(false)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    rowsCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 32)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 14)
                .animation(.easeOut(duration: 0.35), value: appear)
                .onAppear {
                    appear = true
                }
            }
        }
        .toastOverlay($model.toastText)
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 54, height: 54)
                    .shadow(color: .white.opacity(0.16), radius: 14, y: 4)
                Image(systemName: AppBrand.symbol)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundColor(.black)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.tr("Cài Đặt", "Settings"))
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.white)
                Text("\(AppBrand.name) \(DeviceInfo.appVersion)")
                    .font(.footnote)
                    .foregroundColor(Theme.dim)
            }
            Spacer()
        }
        .padding(.bottom, 6)
    }

    // MARK: rows

    private var rowsCard: some View {
        VStack(spacing: 0) {
            row(icon: "globe",
                emoji: model.language == "en" ? "🇺🇸" : "🇻🇳",
                title: model.tr("Ngôn ngữ", "Language"),
                subtitle: model.language == "en" ? "English" : "Tiếng Việt") {
                openLanguage()
            }
            divider
            row(icon: "trash",
                title: model.tr("Xoá Bộ Nhớ Đệm", "Clear Cache"),
                subtitle: model.tr("File tạm trong app", "Temporary app files")) {
                model.clearCache()
            }
            divider
            row(icon: "info.circle",
                title: model.tr("Thông Tin Ứng Dụng", "App Info"),
                subtitle: model.tr("Phiên bản • thiết bị", "Version • device")) {
                model.showToast("\(AppBrand.name) \(DeviceInfo.appVersion)\n\(model.tr("Thiết bị", "Device")): \(DeviceInfo.machine)\niOS: \(DeviceInfo.iosVersion)")
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func row(icon: String, emoji: String? = nil, title: String, subtitle: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.cardHi)
                        .frame(width: 38, height: 38)
                    if let emoji = emoji {
                        Text(emoji)
                            .font(.system(size: 19))
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.dim)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.dimmer)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, 66)
    }

}
