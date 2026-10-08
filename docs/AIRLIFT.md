# AirLift — đọc/ghi container app khác KHÔNG cần kernel exploit

> Tài liệu để dành: cách **Delta Proxy** (iOS) ghi patch vào container Free Fire
> mà không cần jailbreak, không cần exploit kernel. Ghi lại để sau này muốn làm
> đường dự phòng thì có sẵn bản đồ.

## 0. Vì sao cần cái này

Trên máy chưa jailbreak, app bị sandbox — không đọc/ghi được
`/var/mobile/Containers/Data/Application/<game>/Documents/`.
Có 3 đường để vượt:

| Đường | Cần gì | Mức độ |
|---|---|---|
| **Kernel exploit** (app mình đang dùng) | kexploit + sandbox_escape | đã có, chạy tốt |
| **MCM sandbox-extension** (Delta: *"MCM trusted (<27)"*) | chỉ dlopen `libsystem_containermanager` + gọi `container_object_sandbox_extension_activate` | **nhẹ — nên làm trước nếu cần thêm** |
| **AirLift / AFC** (tài liệu này) | pairing file + LocalDevVPN + RSD tunnel + AFC + house_arrest | nặng, nhưng là đường "sạch" nhất (không đụng kernel) |

## 1. AirLift là gì (theo chuỗi trong binary Delta)

Delta nhúng cả crate Rust **`idevice-0.1.68`** và có các module:
`src/exploit.rs`, `al_exploit_run`, `al_find_app_container`, cùng các hàm kiểu CLI:
`imgdelta_tunnel_open`, `imgdelta_pairing_accept_fd`, `imgdelta_house_arrest_list`,
`imgdelta_afc_selftest`, `imgdelta_list_apps`.

Các chuỗi người dùng thấy trong app Delta:

```
This iOS build uses AirLift. Import a pairing file from a computer, then test
the connection before patching. The file is device-specific and may expire after a while.

The tunnel step needs LocalDevVPN loopback (10.7.0.1). Enable it and retry.
Opens the RSD tunnel + AFC (needs LocalDevVPN running)
Self-test (tunnel + AFC) / Read container / Find container (AirTraffic)
```

Và log nội bộ:

```
airlift: parsed Remote Pairing credentials, attempting RSD tunnel on port 49152...
airlift: reading back recovered canary via AFC...
airlift: restored original Books.plist
airlift: cleaning up temporary objects in AFC...
airlift: AirTraffic sync complete
HouseArrest connect_rsd: / AFC connect_rsd:
vend_container(   ...   )            <- gọi dịch vụ house_arrest
airlift: found container for 'com.dts.freefireth'
```

👉 Tóm tắt: **pairing file → VPN loopback → tunnel tới chính máy mình → nói
chuyện lockdownd/RSD → mở dịch vụ house_arrest cho container game → AFC ghi file.**

## 2. Kiến trúc từng lớp

```
┌──────────────────────────── App Delta / BolaMinhDuc ───────────────────────────┐
│                                                                                 │
│  1) Pairing file        (.mobiledevicepairing / *.plist copy từ PC)            │
│         │  chứa: public_key, private_key, identifier, alt_irk, host_id...      │
│         ▼                                                                       │
│  2) LocalDevVPN          app VPN loopback → địa chỉ ảo 10.7.0.1                 │
│         │  (iOS chặn app tự nối vào service hệ thống qua loopback thường;      │
│         │   VPN loopback làm "máy khác" xuất hiện ngay trên máy)                │
│         ▼                                                                       │
│  3) Tunnel tới RSD       TCP tới 10.7.0.1:<port>                                │
│         • iOS ≤16: lockdownd 62078  → StartService(...)                        │
│         • iOS ≥17: Remote Service Discovery (RSD) qua pairing, port 49152      │
│         ▼                                                                       │
│  4) Xác thực phiên        TLS + pair-verify (SRP/Curve25519 + chữ ký)           │
│         ▼                                                                       │
│  5) Dịch vụ cần dùng                                                             │
│         • com.apple.afc                     → AFC filesystem (media dirs)       │
│         • com.apple.mobile.house_arrest     → VendContainer(bundle_id)          │
│         • com.apple.mobile.installation_proxy (tuỳ chọn: list app)              │
│         ▼                                                                       │
│  6) AFC session của container game                                               │
│         WRITE_FILE / FILE_OPEN / WRITE / CLOSE  →                             │
│         /Documents/Assembly-CSharp-patch.bytes                                   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## 3. Việc phải implement (checklist)

1. **Import pairing file**
   - UI chọn file `.mobiledevicepairing`/`.plist` (DocumentPicker).
   - Parse plist: `public_key`, `private_key`, `identifier`, `alt_irk`... (binary plist,
     decode giống `idevice::pairing_file`).
2. **Kiểm tra VPN loopback**
   - Ping/connect `10.7.0.1:<port>`; nếu fail → báo user bật LocalDevVPN.
3. **Tunnel**
   - iOS ≤16: TCP `10.7.0.1:62078` → lockdown → `StartService("com.apple.mobile.house_arrest")`.
   - iOS ≥17: remote pairing handshake → mở **RSD** (HTTP/2), lấy service port,
     rồi CONNECT vào service (xem tài liệu RSD của pymobiledevice3).
4. **AFC** (framing + opcode)
   - Header mỗi packet: `magic "CFA6LPAA"`, `entire_len`, `header_payload_len`,
     `packet_num`, `operation`.
   - Opcode cần: `STATUS`, `DATA`, `MAKE_DIR`, `WRITE_FILE`, `FILE_OPEN`,
     `FILE_WRITE`, `FILE_CLOSE`, `FILE_SET_SIZE`, `RENAME_PATH`, `REMOVE_PATH`,
     `READ_DIR`, `GET_FILE_INFO`.
   - Tham chiếu nguồn mở: `libimobiledevice/afc.h`, `go-ios/afc`, `idevice` (Rust).
5. **house_arrest**
   - Packet đầu: `VendContainer` với `Identifier = <bundle id game>`; response trả
     về cờ OK → từ đó socket là AFC session **đã ở trong container game**.
   - Sau đó đường dẫn trong AFC là tương đối container: `Documents/...`.
6. **Canary + ghi patch** (Delta làm đúng thế)
   - Ghi/đọc thử một file (Delta dùng `Books.plist` của container Books làm canary,
     khôi phục lại sau) → xác nhận AFC thật sự ghi được.
   - `WRITE_FILE` patch vào `Documents/Assembly-CSharp-patch.bytes`, đuôi `.tmp`
     rồi `RENAME_PATH` để thay nguyên tử (an toàn hơn).
   - Dọn file tạm.
7. **Cleanup** — xoá leaf/temp, khôi phục `Books.plist` như Delta.

## 4. Nguồn tham khảo để copy ý tưởng (không phải copy binary)

| Nguồn | Dùng để |
|---|---|
| `jkcoxson/idevice` (Rust) | chính crate Delta nhúng (0.1.68): pairing, RSD, AFC, house_arrest |
| `danielpaulus/go-ios` (Go) | RSD + AFC + house_arrest dễ đọc |
| `doronz88/pymobiledevice3` (Python) | `remote pair`, `--rsd`, `afc`, `house-arrest`; tài liệu iOS 17+ |
| `libimobiledevice` | spec AFC + lockdown kinh điển |
| App **LocalDevVPN** | tạo loopback 10.7.0.1 trên máy |

## 5. Vì sao phải có LocalDevVPN

App sandbox không tự kết nối tới một số service hệ thống trên chính máy qua
loopback. VPN loopback của LocalDevVPN làm các service đó xuất hiện ở địa chỉ
`10.7.0.1` — app chỉ cần connect TCP tới đó là "nói chuyện" được với lockdownd/RSD.
Đây là lý do mọi bản mod kiểu Delta đều yêu cầu pairing file + LocalDevVPN.

## 6. Tự sinh pairing file NGAY TRÊN MÁY (không cần PC)

> Ghi chú kiểm chứng: **3105 KHÔNG có code pairing** (đã grep cả repo: 0 kết quả
> cho pairing/RSD/tunnel). Cái này là của **Delta** và của **StikDebug**.

### Delta tự sinh được — bằng chứng trong binary

```
AirliftPairing
startPairing (bgTask=%lu)
listening on port %u (fd=%d, id=%@)
advertising '%@' on port %u, txt=%@
no device connected (cancelled=%d)
pair-setup rc=%d err=%s
_remotepairing-pairable-host._tcp.
airliftDeviceIRK
delta_pairing.plist            <- file nó tự sinh ra
delta_pairing_import.plist
public_key / private_key / identifier
DeviceCertificate / HostCertificate / HostPrivateKey / RootCertificate
imported pairing file (%llu bytes)
.plist / .mobiledevicepairing / .mobilepair
```

### Cơ chế (host-side pairing qua loopback)

1. App tự chạy **VPN loopback** (10.7.0.1) — không cần LocalDevVPN nếu app tự có
   NetworkExtension (Delta tự lo phần VPN).
2. App **advertise Bonjour** dịch vụ `_remotepairing-pairable-host._tcp.` —
   đóng vai **pairing host** (giống như vai của PC trong flow thường).
3. Daemon `remotepairing` của chính máy (qua loopback) **kết nối ngược vào app**;
   app chạy **pair-setup** (SRP/Curve25519 + trao đổi chứng chỉ) → nhận
   `DeviceCertificate`, cấp `HostCertificate/HostPrivateKey`.
4. App lưu pairing record nội bộ → `delta_pairing.plist`.
   Từ đây nó dùng record đó để mở **RSD tunnel** (mục 3) và AFC/house_arrest —
   hoàn toàn không cần file pairing từ PC.

### Code mẫu nên port từ đâu

| Nguồn | Ghi chú |
|---|---|
| `StikDebug/StikDebug` (GPL) | app iOS **debug/JIT on-device, "powered by idevice"** — làm đúng luồng trên: VPN loopback + pair, tự sinh pairing file ngay trên máy. Đây là bản tham chiếu gần nhất để port. |
| crate `idevice` (Rust, `jkcoxson/idevice`) | chính Delta nhúng (0.1.68): có `pairing_setup`, `rsd`, `afc`, `house_arrest`; StikDebug cũng dùng. |
| `doronz88/pymobiledevice3` | `remote pair` — mô tả rõ message/format của pair-setup iOS 17+. |

### Việc cần làm khi muốn thêm "tự sinh pairing" vào app mình

1. Bật NetworkExtension (nội dung `packet-tunnel-provider`) để có VPN loopback
   (hoặc yêu cầu LocalDevVPN như Delta bản cũ).
2. Publish Bonjour `_remotepairing-pairable-host._tcp.` trên interface VPN.
3. Nhận kết nối pairing → chạy pair-setup host-side (dùng `idevice` qua FFI,
   hoặc port Swift từ StikDebug).
4. Lưu record vào Documents (có thể share/backup), thêm nút Import/Xoá như Delta.
5. Dùng record đó cho RSD tunnel → house_arrest → AFC (mục 3 của tài liệu này).

## 7. Rủi ro / ghi chú

- Pairing file **gắn với từng máy, có thể hết hạn** → phải import lại.
- AFC qua house_arrest có thể bị Apple bịt ở iOS mới; Delta có cả MCM path để chống.
- Việc viết lại toàn bộ RSD + AFC trong Swift là **vài nghìn dòng** — chỉ nên làm
  khi đường kernel/MCM hỏng.
- Ưu tiên thực tế: **MCM** (mục 0) trước, AirLift sau.
