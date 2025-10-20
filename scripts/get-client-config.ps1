param(
  [Parameter(Mandatory=$true)][string]$HostOrIp,
  [Parameter(Mandatory=$true)][string]$PemKeyPath,
  [string]$User = "ubuntu",
  [string]$RemotePath = "~/laptop.conf",
  [string]$OutPath = "$env:USERPROFILE\\Downloads\\laptop.conf"
)

# Yêu cầu: OpenSSH client trong Windows và file .pem được cấp quyền truy cập.
# Ví dụ dùng:
#   .\get-client-config.ps1 -HostOrIp 1.2.3.4 -PemKeyPath C:\path\to\key.pem -RemotePath /root/laptop.conf -OutPath "$env:USERPROFILE\Downloads\laptop.conf"

$scp = Get-Command scp -ErrorAction SilentlyContinue
if (-not $scp) {
  Write-Error "Không tìm thấy lệnh scp. Cài 'OpenSSH Client' trong Optional Features của Windows."
  exit 1
}

$PemKeyPath = (Resolve-Path $PemKeyPath).Path

$cmd = @(
  'scp',
  '-i', $PemKeyPath,
  "$User@$HostOrIp:$RemotePath",
  $OutPath
)

Write-Host "Đang tải file từ $User@$HostOrIp:$RemotePath về $OutPath ..."
& scp -i $PemKeyPath "$User@$HostOrIp:$RemotePath" "$OutPath" | Out-Null

if (Test-Path $OutPath) {
  Write-Host "Tải xong: $OutPath" -ForegroundColor Green
} else {
  Write-Error "Không thể tải file. Kiểm tra lại IP, user, key và quyền truy cập."
}
