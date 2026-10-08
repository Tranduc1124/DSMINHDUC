# BOLA PATCH (iOS)

App iOS tự làm: chạy **kernel exploit + sandbox escape** (lấy từ dự án
[3105](https://github.com/YangJiiii/3105), GPL-3.0) để có quyền đọc/ghi vào
thư mục dữ liệu của app khác — ở đây là **Free Fire** — rồi cài file patch
`Assembly-CSharp-patch.bytes` (file build từ repo `MINHDUC`).

Giao diện SwiftUI tự viết, không dùng app 3105.

## Tính năng

- **KÍCH HOẠT**: chạy `kexploit_opa334` → `sandbox_escape`, hiện log trực tiếp.
- Chọn game: **Free Fire** (`com.dts.freefireth`) / **Free Fire MAX** (`com.dts.freefiremax`).
- **Patch có sẵn trong app** (thư mục `BolaPatch/Patches/`) + **thêm patch từ Files**
  (app bật `UIFileSharingEnabled` nên thấy trong Files app).
- **CÀI PATCH VÀO GAME**: copy patch vào `Documents/Assembly-CSharp-patch.bytes`
  của game, tự backup bản cũ thành `.bak`.
- **Xoá patch**: trả game về trạng thái sạch.

## Build bằng GitHub Actions (không cần Mac)

1. Tạo repo mới trên GitHub (ví dụ `bola-patch`), rồi:

```bash
cd bola-ios
git init -b main
git add .
git commit -m "BolaPatch iOS"
git remote add origin https://github.com/<user>/bola-patch.git
git push -u origin main
```

2. Vào tab **Actions** → workflow `build-ipa` chạy tự động (hoặc bấm
   `Run workflow`). Xong → tải artifact **BolaPatch-unsigned-ipa**.
3. Giải nén được `BolaPatch-unsigned.ipa`, ký bằng **Esign / Sideloadly**
   với **chứng chỉ enterprise** rồi cài lên máy.

> Lưu ý giống 3105: phần can thiệp dữ liệu app khác chỉ hoạt động khi ký bằng
> chứng chỉ enterprise (Esign + cert enterprise), không dùng được SideStore/AltStore.

## Dùng

1. Mở app → bấm **KÍCH HOẠT** (10–30 giây, máy có thể đứng nhẹ; lần đầu fail thì bấm lại).
2. Chọn game + chọn patch (`BolaminhducMenu` có sẵn).
3. Bấm **CÀI PATCH VÀO GAME** → mở game → vào trận, menu `@Bolaminhduc` hiện.

## iOS hỗ trợ (theo exploit gốc)

| iOS | Ghi chú |
|---|---|
| 17.0 – 17.7.x | kernel exploit |
| 18.0 – 18.7.1 | kernel exploit |
| 26.0 – 26.6.1 | cần sandbox escape |
| 27 beta 1–4 | build đã kiểm chứng |

## Cập nhật patch về sau

Sửa `patchsrc/` trong repo `MINHDUC` → `python build_patch.py` → copy
`out/Assembly-CSharp-patch.bytes` vào `BolaPatch/Patches/<Tên>.bytes` → commit/push
→ Actions build IPA mới. Hoặc không cần build lại app: dùng nút **Thêm** để import
file `.bytes` mới từ Files.

## Cấu trúc

```
BolaPatch/
  App/            SwiftUI (ContentView, AppModel, Installer, ExploitRunner…)
  Exploit/        kernel exploit + sandbox escape (vendored từ 3105, GPL-3.0)
  Patches/        patch .bytes đóng sẵn trong app
project.yml       project XcodeGen (CI generate ra .xcodeproj)
.github/workflows/build-ipa.yml
```

Ghi công & giấy phép: xem `LICENSE` (GPL-3.0) và `THIRD_PARTY_NOTICES.md`
(3105 – YangJiii, FilzaSlop/0xjohnnydev, opa334, CrazyMind90 và các tác giả gốc).
