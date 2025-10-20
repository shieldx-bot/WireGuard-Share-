#!/usr/bin/env bash

# add-wireguard-client.sh
# Tạo một Peer (Client) mới cho WireGuard, sinh khóa, cập nhật cấu hình server, và xuất file .conf cho Client.
#
# Sử dụng:
#   sudo bash add-wireguard-client.sh <CLIENT_NAME> [CLIENT_IP]
# Ví dụ:
#   sudo bash add-wireguard-client.sh laptop 10.0.0.2
#
# Biến môi trường tùy chọn:
#   WG_IFACE (mặc định: wg0)
#   WG_CIDR_NET (mặc định: 10.0.0.0/24)
#   WG_SERVER_ADDR (IPv4 của Server trong VPN, mặc định lấy từ WG_IFACE Address đầu tiên)
#   WG_ENDPOINT (địa chỉ public và port, ví dụ: 1.2.3.4:51820) — nếu không đặt, chỉ tạo client.conf trừ Endpoint

set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "[LỖI] Vui lòng chạy với quyền root (sudo)." >&2
  exit 1
fi

WG_IFACE=${WG_IFACE:-wg0}
WG_CIDR_NET=${WG_CIDR_NET:-10.0.0.0/24}
WG_ENDPOINT=${WG_ENDPOINT:-}

if [[ $# -lt 1 ]]; then
  echo "Cách dùng: sudo bash $0 <CLIENT_NAME> [CLIENT_IP]" >&2
  exit 2
fi

CLIENT_NAME="$1"
CLIENT_IP="${2:-}"

CONF_PATH="/etc/wireguard/${WG_IFACE}.conf"
if [[ ! -f "${CONF_PATH}" ]]; then
  echo "[LỖI] Không thấy ${CONF_PATH}. Hãy chạy setup-wireguard-server.sh trước." >&2
  exit 3
fi

SERVER_ADDR_CIDR=$(awk '/^Address\s*=/{print $3; exit}' "${CONF_PATH}")
SERVER_ADDR_VPN=$(echo "${SERVER_ADDR_CIDR}" | cut -d'/' -f1)
SERVER_PREFIX=$(echo "${SERVER_ADDR_CIDR}" | cut -d'/' -f2)
if [[ -z "${SERVER_ADDR_VPN}" ]]; then
  echo "[LỖI] Không trích xuất được địa chỉ VPN của server từ ${CONF_PATH}" >&2
  exit 4
fi
if [[ -z "${SERVER_PREFIX}" ]]; then
  SERVER_PREFIX=24
fi

echo "[+] Sinh key cho Client: ${CLIENT_NAME}"
umask 077
CLIENT_PRIV=$(wg genkey)
CLIENT_PUB=$(printf "%s" "$CLIENT_PRIV" | wg pubkey)

SERVER_PUB=$(cat /etc/wireguard/server_public.key)

if [[ -z "${CLIENT_IP}" ]]; then
  # cấp mặc định theo .2-.254 nếu trống
  base_net=$(echo "$WG_CIDR_NET" | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3"."0}')
  for last in $(seq 2 254); do
    candidate="${base_net%.*}.${last}"
    # Kiểm tra trùng trong file conf
    if ! grep -q "AllowedIPs\s*=\s*${candidate}/32" "${CONF_PATH}"; then
      CLIENT_IP="$candidate"
      break
    fi
  done
  if [[ -z "${CLIENT_IP}" ]]; then
    echo "[LỖI] Không tự gán được IP trống cho client." >&2
    exit 5
  fi
fi

echo "[+] Thêm peer vào Server (${CONF_PATH})"
cat >>"${CONF_PATH}" <<EOF

[Peer]
# ${CLIENT_NAME}
PublicKey = ${CLIENT_PUB}
AllowedIPs = ${CLIENT_IP}/32
EOF

echo "[+] Áp dụng cấu hình mới"
wg syncconf "${WG_IFACE}" <(wg-quick strip "${WG_IFACE}")

CLIENT_CONF="/root/${CLIENT_NAME}.conf"
echo "[+] Tạo cấu hình Client: ${CLIENT_CONF}"
cat >"${CLIENT_CONF}" <<EOF
[Interface]
Address = ${CLIENT_IP}/${SERVER_PREFIX}
PrivateKey = ${CLIENT_PRIV}
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = ${SERVER_PUB}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

if [[ -n "${WG_ENDPOINT}" ]]; then
  echo "Endpoint = ${WG_ENDPOINT}" >> "${CLIENT_CONF}"
else
  echo "# Endpoint = <EC2_PUBLIC_IP>:${WG_PORT:-51820}" >> "${CLIENT_CONF}"
fi

chmod 600 "${CLIENT_CONF}"

echo
echo "Hoàn tất tạo client '${CLIENT_NAME}'." 
echo "- File client: ${CLIENT_CONF}"
echo "- Client IP:   ${CLIENT_IP}"
echo "Gợi ý: tải file .conf này về Windows và import vào ứng dụng WireGuard."
