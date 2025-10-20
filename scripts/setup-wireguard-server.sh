#!/usr/bin/env bash

# setup-wireguard-server.sh
# Cài đặt và cấu hình WireGuard trên Ubuntu (EC2) làm cổng Internet an toàn cho laptop.
# - Cài đặt gói cần thiết
# - Bật IP forwarding
# - Tạo key cho server nếu chưa có
# - Tạo /etc/wireguard/wg0.conf (nếu chưa có) với iptables NAT tự động
# - Khởi động và enable dịch vụ
#
# Biến môi trường tùy chọn:
#   WG_IFACE   (mặc định: wg0)
#   WG_PORT    (mặc định: 51820)
#   WG_CIDR    (mặc định: 10.0.0.1/24)
#   PUB_IFACE  (tự phát hiện từ default route nếu không đặt)
#
# Chạy: sudo bash setup-wireguard-server.sh

set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "[LỖI] Vui lòng chạy với quyền root (sudo)." >&2
  exit 1
fi

WG_IFACE=${WG_IFACE:-wg0}
WG_PORT=${WG_PORT:-51820}
WG_CIDR=${WG_CIDR:-10.0.0.1/24}
PUB_IFACE=${PUB_IFACE:-}

echo "[+] Cài đặt gói hệ thống (wireguard, iptables, iproute2)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends wireguard iproute2 iptables ca-certificates

if [[ -z "${PUB_IFACE}" ]]; then
  PUB_IFACE=$(ip -4 route list default | awk '{print $5}' | head -n1 || true)
fi
if [[ -z "${PUB_IFACE}" ]]; then
  echo "[LỖI] Không phát hiện được giao diện mạng công khai (default route). Hãy đặt biến PUB_IFACE, ví dụ: PUB_IFACE=eth0" >&2
  exit 2
fi

echo "[+] Bật IP forwarding (IPv4) ..."
mkdir -p /etc/sysctl.d
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-wireguard-forwarding.conf
sysctl -p /etc/sysctl.d/99-wireguard-forwarding.conf >/dev/null

echo "[+] Tạo thư mục /etc/wireguard và khóa cho Server (nếu chưa có) ..."
install -d -m 700 /etc/wireguard
if [[ ! -f /etc/wireguard/server_private.key ]]; then
  umask 077
  wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
  echo "[+] Đã tạo server_private.key và server_public.key"
else
  echo "[i] Khóa Server đã tồn tại, bỏ qua bước tạo."
fi

SERVER_PRIV=$(cat /etc/wireguard/server_private.key)
SERVER_PUB=$(cat /etc/wireguard/server_public.key)

CONF_PATH="/etc/wireguard/${WG_IFACE}.conf"

if [[ -f "${CONF_PATH}" ]]; then
  BAK="${CONF_PATH}.bak-$(date +%Y%m%d-%H%M%S)"
  cp -a "${CONF_PATH}" "${BAK}"
  echo "[i] Đã backup cấu hình hiện tại: ${BAK}"
fi

echo "[+] Ghi cấu hình WireGuard: ${CONF_PATH}"
cat >"${CONF_PATH}" <<EOF
[Interface]
# Địa chỉ IP của Server trong mạng VPN
Address = ${WG_CIDR}

# Cổng lắng nghe
ListenPort = ${WG_PORT}

# Khóa riêng tư của Server
PrivateKey = ${SERVER_PRIV}

# Cấu hình NAT và chuyển tiếp bằng iptables
PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${PUB_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${PUB_IFACE} -j MASQUERADE

# Thêm [Peer] của Client ở cuối file này, hoặc dùng script add-wireguard-client.sh
EOF

chmod 600 "${CONF_PATH}"

echo "[+] Khởi động dịch vụ WireGuard (${WG_IFACE}) ..."
systemctl stop "wg-quick@${WG_IFACE}" >/dev/null 2>&1 || true
wg-quick down "${WG_IFACE}" >/dev/null 2>&1 || true
wg-quick up "${WG_IFACE}"
systemctl enable "wg-quick@${WG_IFACE}"

echo
echo "Hoàn tất! Thông tin Server:"
echo "  - Giao diện:     ${WG_IFACE}"
echo "  - Địa chỉ VPN:   ${WG_CIDR}"
echo "  - Cổng:          ${WG_PORT}/udp"
echo "  - Giao diện WAN: ${PUB_IFACE}"
echo "  - Server PubKey: ${SERVER_PUB}"
echo
echo "Tiếp theo: chạy add-wireguard-client.sh để tạo cấu hình cho laptop."
