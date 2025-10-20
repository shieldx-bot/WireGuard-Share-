# Hướng dẫn thiết lập VPN WireGuard với EC2 làm cổng Internet cho Laptop

Tài liệu này bám sát bản thiết kế và bổ sung script tự động hóa. Bạn sẽ có một VPN chạy trên EC2 (Ubuntu) và máy tính Windows kết nối, toàn bộ lưu lượng đi qua EC2.

---

## Quick Start (dễ nhất)

1) Trên EC2 (Ubuntu), chạy 1 lệnh để cài và tạo client đầu tiên:

```bash
sudo bash /path/to/scripts/quick-start.sh
```

Script sẽ tự:
- Cài WireGuard, bật IP forwarding
- Tạo wg0, khởi động dịch vụ
- Lấy IP Public của EC2 và tạo client “laptop” với Endpoint đúng
- In hướng dẫn tải file cấu hình

2) Trên Windows PowerShell, tải file client về (sửa IP và đường dẫn key):

```powershell
scp -i C:\path\to\your-key.pem ubuntu@<EC2_PUBLIC_IP>:/root/laptop.conf C:\Users\$env:USERNAME\Downloads\laptop.conf
```

Hoặc dùng script tiện ích:

```powershell
pwsh -File d:\github\share-internet\scripts\get-client-config.ps1 -HostOrIp <EC2_PUBLIC_IP> -PemKeyPath C:\path\to\your-key.pem -RemotePath /root/laptop.conf -OutPath "$env:USERPROFILE\Downloads\laptop.conf"
```

3) Mở WireGuard trên Windows > Import file laptop.conf > Activate.

Phần dưới đây là hướng dẫn chi tiết nếu bạn muốn kiểm soát từng bước.

## 1) Yêu cầu và tổng quan

- Tài khoản AWS với 1 EC2 Ubuntu 20.04/22.04, IP Public tĩnh (Elastic IP khuyến nghị).
- Bảo mật AWS: mở UDP port 51820 trong Security Group của EC2.
- Máy Windows cài ứng dụng WireGuard.
- Repo này cung cấp:
  - d:\\github\\share-internet\\scripts\\setup-wireguard-server.sh — cài và cấu hình server
  - d:\\github\\share-internet\\scripts\\add-wireguard-client.sh — tạo client và xuất .conf
  - d:\\github\\share-internet\\templates\\*.template — tham khảo cấu hình

Kết quả: laptop dùng IP và băng thông của EC2 khi kết nối VPN.

---

## 2) Cấu hình Security Group trên AWS

1. EC2 > Security Groups > Chọn SG gắn với instance.
2. Inbound rules > Add rule:
   - Type: Custom UDP
   - Port range: 51820
   - Source: 0.0.0.0/0 (hoặc IP của bạn để an toàn hơn)
3. Lưu thay đổi.

---

## 3) Thiết lập trên Server EC2 (Ubuntu)

SSH vào EC2 với quyền sudo. Chạy các lệnh dưới đây. Lưu ý các lệnh phù hợp shell Linux, không chạy trên Windows.

### 3.1. Tải repo (tùy chọn nếu file chưa ở server)

- Nếu bạn đã có 2 script trên server, bỏ qua mục này.
- Hoặc sao chép nội dung các file từ máy bạn lên server (scp/WinSCP).

### 3.2. Phân quyền và chạy script cài đặt

```bash
sudo chmod +x /path/to/scripts/setup-wireguard-server.sh
sudo WG_PORT=51820 bash /path/to/scripts/setup-wireguard-server.sh
```

Ghi chú biến môi trường:
- WG_IFACE: mặc định wg0
- WG_PORT: mặc định 51820/udp
- WG_CIDR: mặc định 10.0.0.1/24 (server .1, dải /24)
- PUB_IFACE: nếu không đặt, script tự phát hiện qua default route (thường là eth0/ens5)

Script sẽ:
- Cài gói wireguard, iptables
- Bật net.ipv4.ip_forward=1
- Tạo server_private.key/server_public.key nếu chưa có
- Tạo /etc/wireguard/wg0.conf với iptables NAT
- Khởi động wg-quick@wg0 và enable boot

Sau khi xong, nó in Server PubKey và thông tin cần thiết.

---

## 4) Tạo cấu hình cho Laptop (Client)

Chạy script thêm client trên EC2:

```bash
sudo chmod +x /path/to/scripts/add-wireguard-client.sh
# Ví dụ tạo client tên "laptop", để script tự cấp IP khả dụng trong dải 10.0.0.0/24
sudo WG_ENDPOINT="<EC2_PUBLIC_IP>:51820" bash /path/to/scripts/add-wireguard-client.sh laptop
```

Ghi chú:
- Có thể chỉ định IP cụ thể: thêm tham số thứ 2, ví dụ 10.0.0.2
- WG_ENDPOINT phải là IP/hostname public của EC2 cộng cổng UDP 51820. Nếu để trống, file client vẫn tạo nhưng Endpoint rỗng (bạn điền thủ công).

Kết quả: file cấu hình client tại /root/laptop.conf. Tải file này về Windows để import.

Tải file về máy Windows (chọn một cách):
- WinSCP: đăng nhập SFTP vào EC2 và tải /root/laptop.conf.
- scp từ Windows PowerShell (cần OpenSSH):

```powershell
# Thay user và địa chỉ IP cho đúng
scp -i C:\\path\\to\\your-key.pem ubuntu@<EC2_PUBLIC_IP>:/root/laptop.conf C:\\Users\\<USER>\\Downloads\\
```

---

## 5) Cấu hình trên Windows (WireGuard Client)

1. Tải và cài WireGuard từ https://www.wireguard.com/install/.
2. Mở WireGuard > Add Tunnel > Import tunnel(s) from file > chọn file laptop.conf vừa tải.
3. Nhấn Activate/Connect.

Nếu kết nối thành công, biểu tượng WireGuard sẽ xanh và bạn có IP 10.0.0.x ở Interface.

---

## 6) Kiểm tra và xác nhận

- Trên EC2: `sudo wg` để xem peer có handshake và transfer dữ liệu không.
- Trên Windows: vào https://ifconfig.me hoặc gõ "what is my ip" trên Google. IP hiển thị phải là IP Public của EC2.
- Ping Internet qua VPN: `ping 1.1.1.1` trong Windows PowerShell khi VPN bật.

---

## 7) Khắc phục sự cố (Troubleshooting)

- Không kết nối được:
  - Kiểm tra Security Group đã mở UDP 51820.
  - Trên EC2 chạy `sudo systemctl status wg-quick@wg0` và `sudo wg`.
  - Kiểm tra Endpoint trong laptop.conf đúng IP:port.
- Kết nối được nhưng không ra Internet:
  - Đảm bảo IP forwarding bật: `sysctl net.ipv4.ip_forward` phải là 1.
  - Kiểm tra iptables NAT có chạy (PostUp/PostDown). Thay `eth0` bằng giao diện thực tế (ens5, enp0s...). Xem giao diện bằng `ip a` hoặc `ip -4 route`.
  - Trên Windows, kiểm tra AllowedIPs = 0.0.0.0/0.
- EC2 reboot xong mất kết nối:
  - `systemctl enable wg-quick@wg0` phải ở trạng thái enabled.
- Nhà mạng chặn UDP 51820:
  - Có thể đổi WG_PORT sang cổng khác, mở lại Security Group. Cập nhật Endpoint ở client.

---

## 8) Bảo mật và thực hành tốt

- Không chia sẻ file private key. Server private key nằm ở /etc/wireguard/server_private.key.
- Thu hồi một client: xóa block [Peer] tương ứng khỏi /etc/wireguard/wg0.conf rồi `sudo wg-quick down wg0 && sudo wg-quick up wg0` hoặc `wg syncconf`.
- Giới hạn Source trong Security Group chỉ IP bạn dùng nếu có thể.

---

## 9) Lệnh nhanh tham khảo (chạy trên EC2)

```bash
# Xem trạng thái
sudo wg
sudo systemctl status wg-quick@wg0

# Làm mới cấu hình sau khi chỉnh /etc/wireguard/wg0.conf
sudo wg-quick down wg0 && sudo wg-quick up wg0
# hoặc
sudo wg syncconf wg0 <(wg-quick strip wg0)
```

---

## 10) Ghi chú nâng cao

- DNS: có thể thay bằng 9.9.9.9, 1.1.1.1, hoặc DNS riêng.
- IPv6: tài liệu này dùng IPv4. Có thể bổ sung Address/AllowedIPs dạng IPv6 nếu cần.
- Nhiều client: chạy script add-wireguard-client.sh nhiều lần với tên khác nhau.

Chúc bạn triển khai thuận lợi! Nếu cần, mình có thể hỗ trợ tinh chỉnh theo hệ điều hành khác hoặc yêu cầu bảo mật cao hơn.
