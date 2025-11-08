#!/bin/bash

# 3Proxy 一键安装脚本
# 支持 Ubuntu/CentOS/Debian
# 包含完整错误检查和自动配置

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查系统类型
check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        log_error "无法检测操作系统"
        exit 1
    fi
    
    log_info "检测到操作系统: $OS $VER"
}

# 检查依赖
check_dependencies() {
    log_info "检查系统依赖..."
    
    local missing_deps=()
    
    for dep in gcc make wget tar; do
        if ! command -v $dep &> /dev/null; then
            missing_deps+=($dep)
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_warning "缺少依赖: ${missing_deps[*]}，开始安装..."
        
        if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
            sudo apt update
            sudo apt install -y build-essential wget make
        elif [[ "$OS" == *"CentOS"* ]] || [[ "$OS" == *"Red Hat"* ]]; then
            sudo yum groupinstall -y "Development Tools"
            sudo yum install -y wget make
        else
            log_error "不支持的操作系统"
            exit 1
        fi
    else
        log_success "所有依赖已安装"
    fi
}

# 检查端口占用
check_port() {
    local port=1080
    log_info "检查端口 $port 是否被占用..."
    
    if sudo netstat -tuln | grep ":$port " > /dev/null; then
        log_warning "端口 $port 已被占用"
        if sudo systemctl is-active --quiet 3proxy; then
            log_info "停止现有的3proxy服务..."
            sudo systemctl stop 3proxy
        fi
        sudo pkill -f "3proxy" || true
        sleep 2
    else
        log_success "端口 $port 可用"
    fi
}

# 下载和编译3proxy
install_3proxy() {
    log_info "开始安装3proxy..."
    
    local temp_dir="/tmp/3proxy_install"
    local version="0.9.4"
    
    # 清理旧文件
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # 下载
    log_info "下载3proxy v$version..."
    if ! wget -q "https://github.com/3proxy/3proxy/archive/$version.tar.gz"; then
        log_error "下载失败"
        exit 1
    fi
    
    # 解压
    tar xzf "$version.tar.gz"
    cd "3proxy-$version"
    
    # 编译
    log_info "编译3proxy..."
    if ! make -f Makefile.Linux > /dev/null 2>&1; then
        log_error "编译失败"
        exit 1
    fi
    
    # 安装
    log_info "安装到系统..."
    if ! sudo make -f Makefile.Linux install > /dev/null 2>&1; then
        log_error "安装失败"
        exit 1
    fi
    
    log_success "3proxy安装完成"
}

# 配置3proxy
configure_3proxy() {
    log_info "配置3proxy..."
    
    local config_dir="/usr/local/3proxy/conf"
    local config_file="$config_dir/3proxy.cfg"
    
    # 创建配置目录
    sudo mkdir -p "$config_dir"
    
    # 生成随机密码
    local user1_pass=$(openssl rand -base64 12 | tr -d '=+/')
    local user2_pass=$(openssl rand -base64 12 | tr -d '=+/')
    
    # 创建配置文件
    sudo tee "$config_file" > /dev/null <<EOF
daemon
nserver 8.8.8.8
nserver 1.1.1.1
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
log /var/log/3proxy.log
logformat "- +_L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T"
auth strong
users proxyuser:CL:${user1_pass} testuser:CL:${user2_pass}
allow proxyuser,testuser
socks -p1080
EOF
    
    # 创建日志文件
    sudo touch /var/log/3proxy.log
    sudo chmod 666 /var/log/3proxy.log
    
    log_success "3proxy配置完成"
    
    # 显示生成的密码
    echo
    log_info "生成的用户凭证："
    echo "========================================"
    echo "用户名: proxyuser"
    echo "密码: $user1_pass"
    echo "----------------------------------------"
    echo "用户名: testuser" 
    echo "密码: $user2_pass"
    echo "========================================"
    echo
}

# 创建系统服务
create_service() {
    log_info "创建系统服务..."
    
    # 检查可执行文件路径
    local proxy_bin="/usr/bin/3proxy"
    if [ ! -f "$proxy_bin" ]; then
        proxy_bin="/bin/3proxy"
    fi
    
    if [ ! -f "$proxy_bin" ]; then
        log_error "找不到3proxy可执行文件"
        exit 1
    fi
    
    # 创建服务文件
    sudo tee /etc/systemd/system/3proxy.service > /dev/null <<EOF
[Unit]
Description=3Proxy Proxy Server
After=network.target

[Service]
Type=forking
ExecStart=$proxy_bin /usr/local/3proxy/conf/3proxy.cfg
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载systemd
    sudo systemctl daemon-reload
    log_success "系统服务创建完成"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    if command -v ufw > /dev/null; then
        sudo ufw allow 1080/tcp
        sudo ufw allow 22/tcp
        sudo ufw allow ssh
        log_success "UFW防火墙已配置"
    elif command -v firewall-cmd > /dev/null; then
        sudo firewall-cmd --permanent --add-port=1080/tcp
        sudo firewall-cmd --reload
        log_success "FirewallD已配置"
    elif command -v iptables > /dev/null; then
        sudo iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
        log_success "iptables已配置"
    else
        log_warning "未找到支持的防火墙工具，请手动开放1080端口"
    fi
}

# 启动服务
start_service() {
    log_info "启动3proxy服务..."
    
    sudo systemctl daemon-reload
    sudo systemctl enable 3proxy
    sudo systemctl start 3proxy
    
    # 等待服务启动
    sleep 3
    
    if sudo systemctl is-active --quiet 3proxy; then
        log_success "3proxy服务启动成功"
    else
        log_error "服务启动失败，检查日志：sudo journalctl -u 3proxy"
        exit 1
    fi
}

# 验证安装
verify_installation() {
    log_info "验证安装..."
    
    # 检查服务状态
    if ! sudo systemctl is-active --quiet 3proxy; then
        log_error "服务未运行"
        return 1
    fi
    
    # 检查端口监听
    if ! sudo netstat -tlnp | grep ":1080 " > /dev/null; then
        log_error "端口1080未监听"
        return 1
    fi
    
    # 测试本地连接
    local user1_pass=$(sudo grep "proxyuser" /usr/local/3proxy/conf/3proxy.cfg | cut -d: -f4)
    
    if curl --socks5 "proxyuser:${user1_pass}@127.0.0.1:1080" -s -o /dev/null -w "%{http_code}" http://httpbin.org/ip | grep -q "200"; then
        log_success "本地连接测试成功"
    else
        log_warning "本地连接测试失败，但服务已启动"
    fi
    
    # 获取公网IP
    local public_ip=$(curl -s http://httpbin.org/ip | grep -oE '"origin":\s*"[^"]+"' | cut -d'"' -f4)
    
    echo
    log_success "🎉 3proxy安装完成！"
    echo
    echo "服务器信息："
    echo "----------------------------------------"
    echo "服务器IP: $public_ip"
    echo "端口: 1080"
    echo "协议: SOCKS5"
    echo "认证: 用户名/密码"
    echo "----------------------------------------"
    echo
    echo "管理命令："
    echo "sudo systemctl status 3proxy    # 查看状态"
    echo "sudo systemctl restart 3proxy   # 重启服务"
    echo "sudo tail -f /var/log/3proxy.log # 查看日志"
    echo
    log_warning "⚠️  请确保云服务商安全组已开放1080端口！"
}

# 主函数
main() {
    echo
    log_info "开始3proxy一键安装..."
    echo "========================================"
    
    check_os
    check_dependencies
    check_port
    install_3proxy
    configure_3proxy
    create_service
    configure_firewall
    start_service
    verify_installation
    
    echo "========================================"
    log_success "安装脚本执行完成"
}

# 运行主函数
main "$@"