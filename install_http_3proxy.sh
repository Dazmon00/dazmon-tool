#!/usr/bin/env bash
# 一鍵安裝 Squid HTTP 代理（僅靠 Basic Auth 驗證，不加 IP 限制）
# 適用 Ubuntu 22.04 / Debian 系
# 2026-03 版本，端口預設 31281，僅 auth 通過即可使用

set -e

# ====================== 自定義區域（請修改這 3 行） ======================
PORT="31281"                   # 代理端口（建議非標準端口，避免掃描）
USERNAME="dazmon"              # 代理帳號
PASSWORD="dazmon888"           # 代理密碼（強烈建議改成更複雜的！）
# ==========================================================================

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}開始安裝/更新 Squid HTTP 代理（僅 auth 驗證）...${NC}"
echo "端口    : $PORT"
echo "帳號    : $USERNAME"
echo ""

# 更新系統 & 安裝必要套件
apt update -qq
apt install -y squid apache2-utils

# 備份原始配置（如果存在的話）
[ -f /etc/squid/squid.conf ] && cp /etc/squid/squid.conf /etc/squid/squid.conf.bak_$(date +%F_%H%M%S)

# 建立/更新密碼文件
HTPASSWD_FILE="/etc/squid/passwd"
htpasswd -bc "$HTPASSWD_FILE" "$USERNAME" "$PASSWORD" >/dev/null 2>&1

chown proxy:proxy "$HTPASSWD_FILE"
chmod 640 "$HTPASSWD_FILE"

echo -e "${GREEN}密碼文件已建立/更新：$HTPASSWD_FILE${NC}"

# 生成極簡配置（移除 IP ACL，只靠 auth）
cat > /etc/squid/squid.conf <<EOF
# Squid 一鍵代理配置 - 僅靠 Basic Auth (無 IP 限制)
# 生成時間: $(date +%Y-%m-%d\ %H:%M:%S)

http_port $PORT
visible_hostname proxy-server

# Basic Authentication (NCSA)
auth_param basic program /usr/lib/squid/basic_ncsa_auth $HTPASSWD_FILE
auth_param basic children 5 startup=5 idle=1
auth_param basic realm "Squid Proxy - Auth Required"
auth_param basic credentialsttl 4 hours
auth_param basic casesensitive off

# ACL 定義
acl auth_users proxy_auth REQUIRED
acl localhost src 127.0.0.1/32

# 訪問控制（順序重要！）
http_access allow localhost
http_access allow auth_users
http_access deny all

# 其他安全建議
via off
forwarded_for off
request_header_access X-Forwarded-For deny all
request_header_access Via deny all
request_header_access Cache-Control deny all
EOF

echo -e "${GREEN}Squid 配置已寫入 /etc/squid/squid.conf${NC}"

# 檢查配置語法
if squid -k parse >/dev/null 2>&1; then
    echo -e "${GREEN}配置語法檢查通過${NC}"
else
    echo -e "${RED}配置語法有錯誤，請檢查 /etc/squid/squid.conf${NC}"
    exit 1
fi

# 重啟服務
systemctl restart squid
systemctl enable squid >/dev/null 2>&1

# 等待服務啟動
sleep 3

if systemctl is-active --quiet squid; then
    echo -e "${GREEN}Squid 服務已啟動${NC}"
else
    echo -e "${RED}Squid 服務啟動失敗，請檢查 journalctl -u squid${NC}"
    exit 1
fi

# ufw 放行（如果 ufw 已啟用）
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow "$PORT"/tcp >/dev/null 2>&1
    ufw reload
    echo -e "${GREEN}ufw 已放行 TCP $PORT${NC}"
fi

echo ""
echo -e "${YELLOW}=== 安裝/更新完成，使用說明 ===${NC}"
echo "代理類型 : HTTP"
echo "伺服器   : 你的 VPS 公網 IP"
echo "端口     : $PORT"
echo "帳號     : $USERNAME"
echo "密碼     : $PASSWORD"
echo ""
echo "Mac Chrome 啟動命令（不帶帳密，讓瀏覽器彈窗驗證）："
echo "open -na \"Google Chrome\" --args \\"
echo "  --user-data-dir=\"\$HOME/Chrome_Profiles/Nado_2\" \\"
echo "  --proxy-server=\"http://你的VPS公網IP:$PORT\""
echo ""
echo "測試命令（終端驗證）："
echo "curl -v -x http://$USERNAME:$PASSWORD@你的VPS公網IP:$PORT http://httpbin.org/ip"
echo ""
echo "注意事項："
echo "1. 第一次在 Chrome 使用時會彈出驗證視窗，輸入帳密後記住"
echo "2. 雲廠商安全組必須放行 TCP $PORT"
echo "3. 如需改密碼或端口，修改腳本開頭變數後重新執行即可"
echo ""
echo -e "${GREEN}祝使用愉快！${NC}"