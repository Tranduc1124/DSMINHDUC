import SwiftUI
import UIKit
import Foundation

/// Tools tab — Astra-style dashboard: kernel/sandbox status, run exploit,
/// verify real write access, iOS support matrix, live log.
struct ToolsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var running = false
    @State private var kernelOK = false
    @State private var sandboxOK = false
    @State private var writeTarget: String?
    @State private var log: [String] = []
    @State private var toast: String?

    private var supported: Bool { ExploitRunner.isSupported() }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    header
                    statusCard
                    actionCard
                    supportCard
                    logCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toastOverlay($toast)
        .onAppear {
            sandboxOK = sandbox_access_is_active() != 0
        }
    }

    // MARK: - header

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("TOOLS")
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(.white)
                .tracking(1.2)
            Text(model.tr("Quyền hệ thống & chẩn đoán",
                          "System access & diagnostics"))
                .font(.caption2)
                .foregroundColor(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - status

    private var statusCard: some View {
        VStack(spacing: 0) {
            statusRow(icon: "cpu",
                      title: "Kernel R/W",
                      value: kernelOK ? model.tr("Đã có", "Active") : model.tr("Chưa chạy", "Not running"),
                      ok: kernelOK)
            divider
            statusRow(icon: "lock.open.fill",
                      title: model.tr("Sandbox", "Sandbox"),
                      value: sandboxOK ? model.tr("Đã thoát (R+W)", "Escaped (R+W)") : model.tr("Chưa có", "Locked"),
                      ok: sandboxOK)
            divider
            statusRow(icon: "externaldrive.fill.badge.checkmark",
                      title: model.tr("Ghi container khác", "Foreign container write"),
                      value: writeTarget == nil
                        ? model.tr("Chưa kiểm tra", "Not tested")
                        : model.tr("OK", "OK"),
                      ok: writeTarget != nil)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Theme.border, lineWidth: 1))
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, 48)
    }

    private func statusRow(icon: String, title: String, value: String, ok: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.cardHi)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(ok ? Color.green : Theme.dimmer)
                    .frame(width: 6, height: 6)
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ok ? .white : Theme.dim)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    // MARK: - actions

    private var actionCard: some View {
        VStack(spacing: 9) {
            Button {
                runExploit()
            } label: {
                HStack(spacing: 8) {
                    if running {
                        ProgressView().tint(.black).scaleEffect(0.8)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(running
                         ? model.tr("ĐANG CHẠY…", "RUNNING…")
                         : model.tr("CHẠY KERNEL EXPLOIT", "RUN KERNEL EXPLOIT"))
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(WhiteButtonStyle())
            .disabled(running)

            Button {
                testWrite()
            } label: {
                Text(model.tr("KIỂM TRA QUYỀN GHI", "TEST WRITE ACCESS"))
                    .font(.system(size: 12.5, weight: .heavy))
                    .tracking(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(running)

            Text(model.tr("Exploit chạy 10–30 giây, máy có thể khựng nhẹ. Không cần jailbreak.",
                          "The exploit takes 10–30s and the device may freeze briefly. No jailbreak needed."))
                .font(.system(size: 10))
                .foregroundColor(Theme.dimmer)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - support

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: supported ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(supported ? .green : .orange)
                Text(supported
                     ? model.tr("Thiết bị được hỗ trợ ghi trực tiếp", "Direct write supported")
                     : model.tr("Ngoài phạm vi ghi trực tiếp", "Outside direct-write range"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text(DeviceInfo.iosVersion)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(Theme.dim)
            }

            Text(model.tr("Ghi trực tiếp: iOS 16.0–18.7.1 và 26.0–26.6.1.\nMáy mới hơn vẫn thử được qua MobileHouseArrest (nếu chứng chỉ giữ đúng bundle id).",
                          "Direct write: iOS 16.0–18.7.1 and 26.0–26.6.1.\nNewer builds can still work through MobileHouseArrest if the certificate keeps the bundle id."))
                .font(.system(size: 10))
                .foregroundColor(Theme.dimmer)
                .fixedSize(horizontal: false, vertical: true)

            Text(DeviceInfo.machine + " · " + DeviceInfo.appVersion)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(Theme.dimmer)
        }
        .padding(13)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - log

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("LOG")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.8)
                    .foregroundColor(Theme.dimmer)
                Spacer()
                if !log.isEmpty {
                    Button {
                        log = []
                    } label: {
                        Text(model.tr("Xoá", "Clear"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Theme.dim)
                    }
                    .buttonStyle(.plain)
                }
            }
            if log.isEmpty {
                Text("—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.dimmer)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(log.suffix(14).enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - actions

    private func runExploit() {
        guard !running else { return }
        running = true
        kernelOK = false
        log = []
        append(model.tr("bắt đầu exploit…", "starting exploit…"))

        DispatchQueue.global(qos: .userInitiated).async {
            let ok = ExploitRunner.run { line in
                DispatchQueue.main.async { self.append(line) }
            }
            DispatchQueue.main.async {
                self.running = false
                self.kernelOK = ok
                self.sandboxOK = sandbox_access_is_active() != 0
                self.append(self.sandboxOK
                       ? self.model.tr("sandbox: đã thoát — ghi được container khác",
                                       "sandbox: escaped — foreign containers writable")
                       : self.model.tr("sandbox: chưa thoát (thử MHA / kiểm tra quyền ghi)",
                                       "sandbox: not escaped (try MHA / test write)"))
                if ok { self.testWrite() }
            }
        }
    }

    private func testWrite() {
        append(model.tr("kiểm tra ghi container…", "testing container write…"))
        DispatchQueue.global(qos: .userInitiated).async {
            let hit = ContainerStore.firstWritableForeignContainer()
            DispatchQueue.main.async {
                self.writeTarget = hit
                if let hit = hit {
                    let name = (hit as NSString).lastPathComponent
                    self.append(self.model.tr("ghi OK → ", "write OK → ") + name)
                    self.toast = self.model.tr("Ghi được container khác ✓",
                                               "Foreign container writable ✓")
                } else {
                    self.append(self.model.tr("chưa ghi được container nào",
                                              "no writable container"))
                    self.toast = self.model.tr("Chưa ghi được — chạy exploit trước",
                                               "Not writable — run the exploit first")
                }
            }
        }
    }

    private func append(_ line: String) {
        log.append(line)
        if log.count > 60 { log.removeFirst(log.count - 60) }
    }
}
