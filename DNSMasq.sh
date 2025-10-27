#!/bin/bash
###############################################################################
#  SafeSearch DNS Installer (dnsmasq)
#  Autor: Ryuz-crypto 🧠
#  Versión: v2.1
#  Descripción:
#     Instala, configura y optimiza dnsmasq como servidor DNS
#     con SafeSearch forzado (Google, YouTube, Bing).
#
#  Características:
#     ✅ Detección automática de interfaz, CPUs y RAM
#     ✅ Configuración dinámica de cache y logging
#     ✅ Bloqueo IPv6 (filter-AAAA)
#     ✅ SafeSearch IPs para Google / YouTube / Bing
#     ✅ Logrotate configurado
#     ✅ 100% automatizado y autoajustado
#
#  Créditos:
#     Script desarrollado y optimizado por Ryuz-crypto 💻
###############################################################################

set -e

echo "=== 🧠 SafeSearch DNS Installer (dnsmasq) ==="
echo "Autor: Ryuz-crypto"
echo ""

# --- 0. Root check ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ Por favor ejecútame con sudo o como root."
  exit 1
fi

# --- 1. Detect hardware (CPU, RAM, interfaz) ---

CPUS=$(nproc)
RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
IFACE=$(ip -o link show | awk -F': ' '$2 !~ /lo/ {print $2; exit}')

echo "🔍 Detectado:"
echo "  • CPU cores : ${CPUS}"
echo "  • RAM total : ${RAM_MB} MB"
echo "  • Interfaz  : ${IFACE}"
echo ""

# --- 2. Parámetros dinámicos según recursos ---

if [ "$RAM_MB" -lt 2048 ]; then
  CACHE_SIZE=50000
elif [ "$RAM_MB" -lt 8192 ]; then
  CACHE_SIZE=100000
elif [ "$RAM_MB" -lt 32768 ]; then
  CACHE_SIZE=200000
else
  CACHE_SIZE=400000
fi

if [ "$CPUS" -lt 8 ]; then
  LOG_QUERIES="false"
else
  LOG_QUERIES="true"
fi

echo "⚙️ Parámetros automáticos:"
echo "  • cache-size      : ${CACHE_SIZE}"
echo "  • log-queries ON? : ${LOG_QUERIES}"
echo ""

# --- 3. Instalar dependencias ---

echo "📦 Instalando dnsmasq y logrotate..."
apt update -qq
apt install -y dnsmasq logrotate

# --- 4. Detener servicios conflictivos ---
echo "🧹 Desactivando servicios DNS conflictivos..."
for svc in bind9 named systemd-resolved; do
  if systemctl list-unit-files | grep -q "^$svc"; then
    systemctl stop $svc || true
    systemctl disable $svc || true
  fi
done

# --- 5. Ajustar resolv.conf ---
echo "🔧 Configurando /etc/resolv.conf..."
rm -f /etc/resolv.conf
echo "nameserver 127.0.0.1" > /etc/resolv.conf

# --- 6. Crear configuración dnsmasq ---
echo "🧾 Generando /etc/dnsmasq.conf..."

if [ "$LOG_QUERIES" = "true" ]; then
  LOG_BLOCK=$(cat <<'EOFLOG'
# Logging detallado de consultas DNS
log-queries
log-facility=/var/log/dnsmasq.log
EOFLOG
)
else
  LOG_BLOCK=$(cat <<'EOFLOG'
# Logging básico (sin consultas detalladas)
log-facility=/var/log/dnsmasq.log
EOFLOG
)
fi

cat > /etc/dnsmasq.conf <<EOF
###############################################################################
# dnsmasq configurado automáticamente por Ryuz-crypto
###############################################################################

# Interfaz principal
interface=${IFACE}
bind-interfaces
listen-address=0.0.0.0
except-interface=lo

# Sin DHCP
no-dhcp-interface=${IFACE}
no-dhcp-interface=lo
dhcp-range=

# Solo IPv4, evitar AAAA (IPv6)
no-resolv
no-hosts
filter-AAAA

# DNS Upstream
server=1.1.1.1
server=8.8.8.8

# Caché
cache-size=${CACHE_SIZE}
no-negcache

# Hardening
bogus-priv
stop-dns-rebind

# --- SafeSearch Overrides ---
# Google SafeSearch
address=/www.google.com/216.239.38.120
address=/google.com/216.239.38.120

# YouTube Restricted Mode
address=/www.youtube.com/216.239.38.120
address=/youtube.com/216.239.38.120

# Bing Strict SafeSearch
address=/www.bing.com/204.79.197.220
address=/bing.com/204.79.197.220

# Logging
${LOG_BLOCK}
EOF

# --- 7. Logrotate ---
echo "🌀 Configurando rotación de logs..."
touch /var/log/dnsmasq.log
chown dnsmasq:dnsmasq /var/log/dnsmasq.log || true
chmod 640 /var/log/dnsmasq.log || true

cat > /etc/logrotate.d/dnsmasq <<'EOF'
/var/log/dnsmasq.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    create 640 dnsmasq dnsmasq
    postrotate
        systemctl kill -s HUP dnsmasq >/dev/null 2>&1 || true
    endscript
}
EOF

# --- 8. Activar dnsmasq ---
echo "🚀 Reiniciando y habilitando dnsmasq..."
systemctl restart dnsmasq
systemctl enable dnsmasq

# --- 9. Verificación ---
echo "🔎 Prueba local:"
echo "dig @127.0.0.1 www.google.com +short"
dig @127.0.0.1 www.google.com +short || true
echo "dig @127.0.0.1 www.youtube.com +short"
dig @127.0.0.1 www.youtube.com +short || true
echo "dig @127.0.0.1 www.bing.com +short"
dig @127.0.0.1 www.bing.com +short || true

echo ""
echo "✅ Instalación completada correctamente."
echo "Servidor DNS SafeSearch activo por Ryuz-crypto 🚀"
echo ""
echo "👉 Pasos finales en cliente Windows:"
echo "1) Configura el DNS preferido como la IP de este servidor."
echo "2) Ejecuta: ipconfig /flushdns"
echo "3) Verifica: nslookup www.google.com <IP_DE_ESTE_SERVIDOR>"
echo ""
echo "Si ves '216.239.38.120' → SafeSearch está forzado correctamente."
###############################################################################
