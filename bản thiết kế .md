Chào bạn\! Rất vui được hỗ trợ bạn trong dự án này. Việc biến VPS Amazon EC2 thành một cổng kết nối internet cá nhân cho laptop là một ý tưởng tuyệt vời để tận dụng tốc độ mạng cao và có một kết nối an toàn.

Mục tiêu của chúng ta là thiết lập một **Mạng Riêng Ảo (VPN)**. Laptop của bạn sẽ tạo một "đường hầm" được mã hóa và an toàn đến VPS. Toàn bộ dữ liệu internet từ laptop sẽ đi qua đường hầm này, đến VPS, rồi mới đi ra ngoài internet. Bằng cách này, laptop của bạn sẽ sử dụng địa chỉ IP và kết nối mạng của VPS.

Hãy cùng tôi xem qua bản thiết kế chi tiết nhé.

-----

### **Tổng quan về Giải pháp**

Chúng ta sẽ cài đặt một phần mềm VPN tên là **WireGuard** trên VPS Amazon EC2. WireGuard nổi tiếng vì tốc độ nhanh, dễ cài đặt và bảo mật cao.

**Luồng hoạt động sẽ như sau:**

1.  **Cài đặt Server WireGuard:** Trên VPS EC2.
2.  **Cài đặt Client WireGuard:** Trên laptop của bạn.
3.  **Tạo cặp khóa an toàn:** Một cặp cho server và một cặp cho client để xác thực và mã hóa dữ liệu.
4.  **Cấu hình kết nối:** Thiết lập các quy tắc để server chấp nhận kết nối từ client và định tuyến lưu lượng truy cập internet ra ngoài.

-----

### **Bước 1: Chuẩn bị trên Amazon EC2**

Trước khi bắt đầu, chúng ta cần đảm bảo VPS của bạn sẵn sàng.

1.  **Chọn một VPS:** Một phiên bản `t2.micro` hoặc `t3.micro` của Amazon EC2 (thường có trong gói miễn phí) là quá đủ cho mục đích cá nhân.
2.  **Hệ điều hành:** Tôi khuyên bạn nên dùng **Ubuntu 22.04** hoặc **Ubuntu 20.04** vì chúng rất phổ biến và có nhiều tài liệu hướng dẫn.
3.  **Cấu hình Security Group (Tường lửa):** Đây là bước cực kỳ quan trọng. Bạn cần cho phép lưu lượng truy cập đi vào VPS qua cổng mà WireGuard sẽ sử dụng.
      * Trong bảng điều khiển AWS EC2, vào phần "Security Groups".
      * Chọn security group gắn với VPS của bạn.
      * Thêm một "Inbound rule" (Luật đi vào) mới với các thông số sau:
          * **Type (Loại):** `Custom UDP`
          * **Port Range (Dải cổng):** `51820` (Đây là cổng mặc định của WireGuard, bạn có thể chọn cổng khác nếu muốn).
          * **Source (Nguồn):** `Anywhere` (0.0.0.0/0) để bạn có thể kết nối từ bất kỳ đâu.

-----

### **Bước 2: Thiết kế và Mã nguồn (Cài đặt trên Server)**

Bây giờ, chúng ta sẽ đi vào phần chính: cài đặt và cấu hình WireGuard trên VPS. Bạn hãy kết nối với VPS của mình qua SSH để thực hiện các lệnh sau.

#### **1. Cập nhật hệ thống và cài đặt WireGuard**

Đầu tiên, hãy đảm bảo hệ thống của bạn được cập nhật và cài đặt gói `wireguard`.

```bash
# Cập nhật danh sách gói phần mềm
sudo apt update

# Nâng cấp các gói đã cài đặt
sudo apt upgrade -y

# Cài đặt WireGuard
sudo apt install wireguard -y
```

#### **2. Kích hoạt chuyển tiếp IP (IP Forwarding)**

Để VPS có thể "chuyển tiếp" lưu lượng mạng từ laptop của bạn ra internet, chúng ta cần bật tính năng này.

```bash
# Mở file cấu hình hệ thống
sudo nano /etc/sysctl.conf
```

Trong file vừa mở, hãy tìm dòng `#net.ipv4.ip_forward=1`, xóa dấu `#` ở đầu để kích hoạt nó. Nếu không có dòng đó, hãy thêm dòng sau vào cuối file:

```
net.ipv4.ip_forward=1
```

Lưu file lại (nhấn `Ctrl + X`, sau đó `Y`, và `Enter`). Sau đó, áp dụng thay đổi ngay lập tức:

```bash
sudo sysctl -p
```

#### **3. Tạo khóa cho Server**

Mỗi bên (server và client) cần có một cặp khóa: khóa riêng tư (private key) để giữ bí mật và khóa công khai (public key) để chia sẻ.

```bash
# Đặt quyền truy cập cho thư mục WireGuard để bảo mật
sudo umask 077

# Tạo cặp khóa và lưu vào thư mục /etc/wireguard/
sudo wg genkey | sudo tee /etc/wireguard/server_private.key | sudo wg pubkey | sudo tee /etc/wireguard/server_public.key
```

#### **4. Tạo file cấu hình cho Server**

Đây là trái tim của việc thiết lập. Chúng ta sẽ tạo một file cấu hình định nghĩa mạng VPN.

```bash
# Mở file cấu hình mới
sudo nano /etc/wireguard/wg0.conf
```

Hãy sao chép và dán nội dung sau vào file. Tôi đã thêm giải thích cho từng dòng.

```ini
[Interface]
# Địa chỉ IP riêng của Server trong mạng VPN.
Address = 10.0.0.1/24

# Cổng mà Server sẽ lắng nghe kết nối. Phải khớp với cổng bạn mở trong Security Group.
ListenPort = 51820

# Khóa riêng tư của Server.
# Chạy lệnh `sudo cat /etc/wireguard/server_private.key` và dán kết quả vào đây.
PrivateKey = <NỘI DUNG KHÓA RIÊNG TƯ CỦA SERVER>

# Các lệnh này sẽ tự động chạy khi VPN khởi động/tắt để cấu hình tường lửa (iptables).
# Chúng cho phép lưu lượng từ VPN (10.0.0.0/24) đi ra ngoài internet qua giao diện mạng chính (eth0).
# Lưu ý: Tên giao diện mạng `eth0` có thể khác trên VPS của bạn. Chạy lệnh `ip a` để kiểm tra.
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# --- Dưới đây là thông tin của Client (Laptop) sẽ được thêm vào sau ---
# [Peer]
# PublicKey = <NỘI DUNG KHÓA CÔNG KHAI CỦA CLIENT>
# AllowedIPs = 10.0.0.2/32
```

**Quan trọng:** Bạn cần thay thế `<NỘI DUNG KHÓA RIÊNG TƯ CỦA SERVER>` bằng cách chạy lệnh `sudo cat /etc/wireguard/server_private.key` trên terminal và dán kết quả vào.

#### **5. Khởi động Server WireGuard**

```bash
# Bật giao diện VPN wg0
sudo wg-quick up wg0

# Cấu hình để WireGuard tự khởi động cùng hệ thống
sudo systemctl enable wg-quick@wg0
```

Để kiểm tra xem server đã chạy chưa, gõ lệnh `sudo wg`. Bạn sẽ thấy thông tin về giao diện `wg0` đang hoạt động.

-----

### **Bước 3: Thiết kế và Mã nguồn (Cài đặt trên Laptop)**

Bây giờ, chúng ta sẽ cấu hình trên máy tính xách tay của bạn.

#### **1. Cài đặt ứng dụng WireGuard Client**

Truy cập trang chủ của WireGuard ([https://www.wireguard.com/install/](https://www.wireguard.com/install/)) và tải về ứng dụng phù hợp với hệ điều hành của bạn (Windows, macOS, Linux).

#### **2. Tạo khóa cho Client**

Tương tự như server, client cũng cần một cặp khóa. Ứng dụng WireGuard trên Windows và macOS thường có nút để tự động tạo cặp khóa này cho bạn.

Nếu bạn dùng Linux hoặc muốn tạo thủ công:

```bash
# Tạo khóa cho client
wg genkey | tee client_private.key | wg pubkey > client_public.key
```

Lệnh này sẽ tạo ra 2 file: `client_private.key` và `client_public.key`. **Hãy giữ bí mật file private key\!**

#### **3. Tạo file cấu hình cho Client**

Mở ứng dụng WireGuard Client và tạo một kết nối mới (hoặc tạo một file `.conf`). Nhập vào nội dung sau:

```ini
[Interface]
# Địa chỉ IP riêng của Client trong mạng VPN.
Address = 10.0.0.2/24

# Khóa riêng tư của Client.
PrivateKey = <NỘI DUNG KHÓA RIÊNG TƯ CỦA CLIENT>

[Peer]
# Khóa công khai của Server.
# Chạy lệnh `sudo cat /etc/wireguard/server_public.key` trên VPS và dán kết quả vào đây.
PublicKey = <NỘI DUNG KHÓA CÔNG KHAI CỦA SERVER>

# Dòng này chỉ định rằng tất cả lưu lượng internet (0.0.0.0/0) sẽ được gửi qua VPN.
AllowedIPs = 0.0.0.0/0

# Địa chỉ IP công khai của VPS và cổng WireGuard.
# Ví dụ: 54.123.45.67:51820
Endpoint = <ĐỊA CHỈ IP CÔNG KHAI CỦA VPS>:51820
```

**Quan trọng:**

  * Thay thế `<NỘI DUNG KHÓA RIÊNG TƯ CỦA CLIENT>` bằng khóa riêng tư bạn vừa tạo.
  * Thay thế `<NỘI DUNG KHÓA CÔNG KHAI CỦA SERVER>` bằng cách lấy nó từ VPS (`sudo cat /etc/wireguard/server_public.key`).
  * Thay thế `<ĐỊA CHỈ IP CÔNG KHAI CỦA VPS>` bằng IP public của EC2 instance.

-----

### **Bước 4: Hoàn tất kết nối**

Chúng ta chỉ còn một bước cuối cùng: "giới thiệu" client cho server biết.

1.  **Lấy khóa công khai của client:** Lấy nội dung khóa công khai bạn đã tạo ở Bước 3.
2.  **Cập nhật file cấu hình trên server:** Mở lại file `/etc/wireguard/wg0.conf` trên VPS.
    ```bash
    sudo nano /etc/wireguard/wg0.conf
    ```
3.  Thêm đoạn sau vào cuối file:
    ```ini
    [Peer]
    # Khóa công khai của laptop
    PublicKey = <NỘI DUNG KHÓA CÔNG KHAI CỦA CLIENT>

    # Địa chỉ IP mà chúng ta cấp cho laptop này
    AllowedIPs = 10.0.0.2/32
    ```
4.  **Khởi động lại WireGuard trên server** để áp dụng thay đổi:
    ```bash
    sudo wg-quick down wg0 && sudo wg-quick up wg0
    ```

Bây giờ, trên laptop của bạn, hãy mở ứng dụng WireGuard và nhấn nút **"Activate"** hoặc **"Connect"**. Nếu mọi thứ chính xác, kết nối sẽ được thiết lập thành công\!

Bạn có thể kiểm tra địa chỉ IP của mình trên Google (tìm "what is my ip") để xác nhận rằng bạn đang sử dụng IP của VPS.

Chúc mừng bạn đã hoàn thành\! Nếu bạn gặp bất kỳ khó khăn nào trong quá trình thực hiện, đừng ngần ngại hỏi nhé. Tôi luôn sẵn sàng giúp bạn sửa lỗi và tinh chỉnh mã.