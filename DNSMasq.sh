#!/bin/bash
###############################################################################
#  SafeSearch DNS Installer (dnsmasq)
#  Autor: Ryuz-crypto
#  Versión: v2.4
#
#  Objetivo:
#    - Levantar dnsmasq como servidor DNS con SafeSearch obligatorio
#      (Google / YouTube / Bing) SIN servir DHCP.
###############################################################################

set -e

echo "=== 🧠 SafeSearch DNS Installer v2.4 ==="
echo "Autor: Ryuz-crypto"
echo ""

if [ "$EUID" -ne 0 ]; then
  echo "❌ Ejecuta con sudo o como root."
  exit 1
fi

echo "🔍 Detectando hardware e interfaz de red..."

CPUS=$(nproc)
RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)

IFACE=$(ip -o link show up | awk -F': ' '$2 !~ /lo/ {print $2; exit}')
if [ -z "$IFACE" ]; then
    IFACE="eth0"
fi

echo "  • CPU cores : ${CPUS}"
echo "  • RAM total : ${RAM_MB} MB"
echo "  • Interfaz  : ${IFACE}"
echo ""


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
  LOG_QUERIES=false
else
  LOG_QUERIES=true
fi

echo " Parámetros automáticos:"
echo "  • cache-size      : ${CACHE_SIZE}"
echo "  • log-queries ON? : ${LOG_QUERIES}"
echo ""

echo " Instalando dependencias (dnsmasq, logrotate)..."
apt update -qq
apt install -y dnsmasq logrotate

echo " Deshabilitando servicios conflictivos (bind9/named/systemd-resolved)..."

SERVICES=("bind9" "named" "systemd-resolved")
for svc in "${SERVICES[@]}"; do
  if systemctl list-unit-files | grep -q "^$svc"; then
    systemctl stop "$svc" || true
    systemctl disable "$svc" || true
  fi
done

echo " Verificando procesos en puerto 53 y limpiando..."
PIDS_ON_53=$(ss -lntup | awk '/:53 / {print $NF}' | sed 's/.*pid=\([0-9]\+\).*/\1/' | sort -u)
if [ -n "$PIDS_ON_53" ]; then
  echo "   Procesos en 53: $PIDS_ON_53"
  for pid in $PIDS_ON_53; do
    kill -9 "$pid" || true
  done
fi

echo " Configurando /etc/resolv.conf -> 127.0.0.1 ..."
rm -f /etc/resolv.conf
echo "nameserver 127.0.0.1" > /etc/resolv.conf

# --- 6. Bloque de logging dinámico ---
if [ "$LOG_QUERIES" = true ]; then
  LOG_BLOCK="log-queries
log-facility=/var/log/dnsmasq.log"
else
  LOG_BLOCK="log-facility=/var/log/dnsmasq.log"
fi

echo " Generando /etc/dnsmasq.conf ..."

cat > /etc/dnsmasq.conf <<EOF


interface=${IFACE}

bind-interfaces

no-resolv
no-hosts

server=1.1.1.1
server=8.8.8.8

cache-size=${CACHE_SIZE}
no-negcache

bogus-priv
stop-dns-rebind

# Google SafeSearch (forcesafesearch.google.com ~ 216.239.38.120)
address=/www.google.com/216.239.38.120
address=/google.com/216.239.38.120

address=/www.youtube.com/216.239.38.120
address=/youtube.com/216.239.38.120

address=/www.bing.com/204.79.197.220
address=/bing.com/204.79.197.220

# Logging dinámico
${LOG_BLOCK}
EOF

echo "🌀 Configurando log y logrotate..."
touch /var/log/dnsmasq.log
chmod 666 /var/log/dnsmasq.log

cat > /etc/logrotate.d/dnsmasq <<'EOF'
/var/log/dnsmasq.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    create 640 root root
    postrotate
        systemctl kill -s HUP dnsmasq >/dev/null 2>&1 || true
    endscript
}
EOF

echo " Validando sintaxis con 'dnsmasq --test' ..."
if ! dnsmasq --test; then
    echo " ERROR: La configuración de /etc/dnsmasq.conf falló la validación."
    echo "Revisa el mensaje de error de 'dnsmasq --test' arriba y corrige."
    exit 1
fi
echo " Sintaxis OK."

echo "🚀 Iniciando y habilitando dnsmasq..."
systemctl daemon-reload
systemctl restart dnsmasq
systemctl enable dnsmasq

systemctl --no-pager status dnsmasq || true

echo " Prueba de resolución SafeSearch:"
echo "dig @127.0.0.1 www.google.com +short"
dig @127.0.0.1 www.google.com +short || true
echo "dig @127.0.0.1 www.youtube.com +short"
dig @127.0.0.1 www.youtube.com +short || true
echo "dig @127.0.0.1 www.bing.com +short"
dig @127.0.0.1 www.bing.com +short || true

echo ""
echo "Script por Ryuz-crypto "
###############################################################################

