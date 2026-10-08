import SwiftUI

/// CÀI ĐẶT — Delta-style sheet: big header, rounded rows card.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    rowsCard
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 26)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.cardHi)
                    .frame(width: 52, height: 52)
                Image(systemName: "gearshape")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Cài Đặt")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(.white)
                Text("BOLAMINHDUC \(DeviceInfo.appVersion)")
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
            row(icon: "bolt.fill", title: "Chạy Lại Kernel",
                subtitle: "Kích hoạt lại exploit nếu INJECT báo lỗi") {
                model.rerunKernel()
            }
            divider
            row(icon: "trash", title: "Xoá Bộ Nhớ Đệm",
                subtitle: "File tạm trong app") {
                model.clearCache()
            }
            divider
            row(icon: "info.circle", title: "Thông Tin Ứng Dụng",
                subtitle: "Phiên bản • thiết bị • patch") {
                model.alertText = """
                BOLAMINHDUC \(DeviceInfo.appVersion)
                Máy: \(DeviceInfo.machine)
                Hệ điều hành: \(DeviceInfo.iosVersion)
                Patch: \(model.bundledPatch?.name ?? "—")
                """
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func row(icon: String, title: String, subtitle: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Theme.cardHi)
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
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
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, 66)
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(model.statusText)
                .font(.caption)
                .foregroundColor(Theme.dim)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var statusColor: Color {
        switch model.phase {
        case .idle: return Theme.dimmer
        case .running: return .yellow
        case .active: return .green
        case .failed: return .red
        }
    }
}
