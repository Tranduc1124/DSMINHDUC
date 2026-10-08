import SwiftUI
import UIKit

/// Tab 2 — CÀI ĐẶT (Delta-style rows, monochrome)
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var shareURL: URL?

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
        .background(ShareSheetPresenter(url: $shareURL))
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
            row(icon: "arrow.triangle.2.circlepath", title: "Kiểm tra cập nhật",
                subtitle: model.latestTag.isEmpty
                    ? "So sánh với GitHub Releases"
                    : "Bản mới nhất: \(model.latestTag)") {
                model.checkUpdate()
            }
            divider
            row(icon: "safari", title: "Tải bản mới trên GitHub",
                subtitle: "Mở trang Releases") {
                openURL(releasesPage)
            }
            divider
            row(icon: "trash", title: "Xoá bộ nhớ đệm",
                subtitle: "File tạm trong app") {
                model.clearCache()
            }
            divider
            row(icon: "square.and.arrow.up", title: "Chia sẻ ứng dụng",
                subtitle: "Gửi link tải cho bạn bè") {
                shareURL = URL(string: releasesPage)
            }
            divider
            row(icon: "info.circle", title: "Thông tin ứng dụng",
                subtitle: "\(DeviceInfo.machine) • \(DeviceInfo.iosVersion)") {
                model.alertText = """
                BOLAMINHDUC \(DeviceInfo.appVersion)
                Máy: \(DeviceInfo.machine)
                Hệ điều hành: \(DeviceInfo.iosVersion)
                Patch đang có: \(model.patches.count)
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

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }
}

/// tiny presenter that shows a UIActivityViewController when `url` is set
struct ShareSheetPresenter: UIViewControllerRepresentable {
    @Binding var url: URL?

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        guard let url, host.presentedViewController == nil else { return }
        DispatchQueue.main.async {
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            host.present(activity, animated: true)
            self.url = nil
        }
    }
}
