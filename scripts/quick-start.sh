#!/usr/bin/env bash

# quick-start.sh
# Thiết lập WireGuard Server trên EC2 và tạo Client đầu tiên trong 1 lần chạy.
# - Cài đặt gói cần thiết
# - Bật IP forwarding
# - Tạo cấu hình wg0
# - Tự nhận IP public từ EC2 metadata
# - Tạo client đầu tiên và in hướng dẫn tải về

set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "[LỖI] Vui lòng chạy với quyền root (sudo)." >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Tham số nhanh (có thể override qua biến môi trường)
WG_IFACE=${WG_IFACE:-wg0}
WG_PORT=${WG_PORT:-51820}
WG_CIDR=${WG_CIDR:-10.0.0.1/24}
CLIENT_NAME=${CLIENT_NAME:-laptop}

echo "[+] Cài đặt gói hệ thống ..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends wireguard iproute2 iptables ca-certificates curl qrencode >/dev/null

# Phát hiện interface ra Internet
PUB_IFACE=${PUB_IFACE:-}
if [[ -z "${PUB_IFACE}" ]]; then
  PUB_IFACE=$(ip -4 route list default | awk '{print $5}' | head -n1 || true)
fi
if [[ -z "${PUB_IFACE}" ]]; then
  echo "[LỖI] Không phát hiện được giao diện mạng công khai. Đặt PUB_IFACE, ví dụ PUB_IFACE=eth0" >&2
  exit 2
fi

echo "[+] Bật IP forwarding ..."
mkdir -p /etc/sysctl.d
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-wireguard-forwarding.conf
sysctl -p /etc/sysctl.d/99-wireguard-forwarding.conf >/dev/null

# Khóa server
install -d -m 700 /etc/wireguard
if [[ ! -f /etc/wireguard/server_private.key ]]; then
  umask 077
  wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
fi
SERVER_PRIV=$(cat /etc/wireguard/server_private.key)
SERVER_PUB=$(cat /etc/wireguard/server_public.key)

CONF_PATH="/etc/wireguard/${WG_IFACE}.conf"
if [[ ! -f "${CONF_PATH}" ]]; then
  echo "[+] Tạo cấu hình ${CONF_PATH}"
  cat >"${CONF_PATH}" <<EOF
[Interface]
Address = ${WG_CIDR}
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV}
PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${PUB_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${PUB_IFACE} -j MASQUERADE
EOF
  chmod 600 "${CONF_PATH}"
else
  echo "[i] Đã có ${CONF_PATH}, giữ nguyên và tiếp tục."
fi

echo "[+] Khởi động WireGuard (${WG_IFACE})"
systemctl stop "wg-quick@${WG_IFACE}" >/dev/null 2>&1 || true
wg-quick down "${WG_IFACE}" >/dev/null 2>&1 || true
wg-quick up "${WG_IFACE}"
systemctl enable "wg-quick@${WG_IFACE}" >/dev/null

# Lấy IP public từ EC2 metadata (ưu tiên)
EC2_PUBLIC_IP=$(curl -fs http://169.254.169.254/latest/meta-data/public-ipv4 || true)
if [[ -z "${EC2_PUBLIC_IP}" ]]; then
  # fallback nhẹ nhàng: thử hostname -I (không luôn đúng Public IP)
  EC2_PUBLIC_IP=$(curl -fs https://ifconfig.me || echo "<EC2_PUBLIC_IP>")
fi
WG_ENDPOINT="${EC2_PUBLIC_IP}:${WG_PORT}"

echo "[+] Tạo client đầu tiên: ${CLIENT_NAME}"
if [[ -x "${SCRIPT_DIR}/add-wireguard-client.sh" ]]; then
  WG_ENDPOINT="${WG_ENDPOINT}" bash "${SCRIPT_DIR}/add-wireguard-client.sh" "${CLIENT_NAME}"
else
  # fallback: gọi từ PATH nếu đã cài đặt vào vị trí khác
  WG_ENDPOINT="${WG_ENDPOINT}" bash add-wireguard-client.sh "${CLIENT_NAME}"
fi

CLIENT_CONF="/root/${CLIENT_NAME}.conf"

echo
echo "Hoàn tất Quick Start!"
echo "- Server PubKey: ${SERVER_PUB}"
echo "- Endpoint:      ${WG_ENDPOINT}"
echo "- File client:   ${CLIENT_CONF}"
echo
if command -v qrencode >/dev/null 2>&1; then
  echo "[QR] Quét QR (tiện cho điện thoại):"
  echo
  cat "${CLIENT_CONF}" | qrencode -t ansiutf8 -l L
  echo
fi

echo "Gợi ý tải về file client từ Windows PowerShell (sửa đường dẫn key và IP):"
echo "scp -i C:\\path\\to\\your-key.pem ubuntu@${EC2_PUBLIC_IP}:${CLIENT_CONF} C:\\Users\\%USERNAME%\\Downloads\\${CLIENT_NAME}.conf"
