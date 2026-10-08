import SwiftUI
import UIKit

/// Tab 2 — CÀI ĐẶT (Delta-style rows, monochrome)
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    private let releasesPage = "https://github.com/Tranduc1124/DSMINHDUC/releases/latest"

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                rows
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 34))
                .foregroundColor(.white)
            Text("Cài Đặt")
                .font(.title2.weight(.heavy))
                .foregroundColor(.white)
            Text("BOLAMINHDUC \(DeviceInfo.appVersion)")
                .font(.caption)
                .foregroundColor(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .card()
    }

    private var rows: some View {
        VStack(spacing: 0) {
            row(icon: "bolt.fill", title: "Chạy lại kernel",
                subtitle: "Kích hoạt lại exploit nếu INJECT báo lỗi") {
                model.rerunKernel()
            }
            divider
            row(icon: "trash", title: "Xoá bộ nhớ đệm",
                subtitle: "File tạm trong app") {
                model.clearCache()
            }
            divider
            row(icon: "doc.on.doc", title: "Sao chép link tải",
                subtitle: "Copy link tải app cho bạn bè") {
                UIPasteboard.general.string = releasesPage
                model.alertText = "Đã sao chép link tải:\n\(releasesPage)"
            }
            divider
            row(icon: "info.circle", title: "Thông tin ứng dụng",
                subtitle: "\(DeviceInfo.machine) • \(DeviceInfo.iosVersion)") {
                model.alertText = """
                BOLAMINHDUC \(DeviceInfo.appVersion)
                Máy: \(DeviceInfo.machine)
                Hệ điều hành: \(DeviceInfo.iosVersion)
                Patch: \(model.bundledPatch?.name ?? "—")
                """
            }
        }
        .card(padding: 0)
    }

    private func row(icon: String, title: String, subtitle: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(Theme.dimmer)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.dimmer)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, 52)
    }
}
