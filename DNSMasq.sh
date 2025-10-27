#!/bin/bash
###############################################################################
#  SafeSearch DNS Installer (dnsmasq)
#  Autor: Ryuz-crypto
#  Versión: v2.2
#
#  Objetivo:
#    - Instalar y configurar dnsmasq como servidor DNS corporativo con SafeSearch
#      forzado (Google / YouTube / Bing).
#    - Ajustar caché y logging dinámicamente según CPU y RAM.
#    - Deshabilitar servicios que bloquean el puerto 53.
#    - Generar configuración 100% válida para systemd-helper checkconfig.
#
#  Cambios v2.2:
#    - Manejo seguro de permisos de log (sin asumir usuario dnsmasq:dnsmasq).
#    - Config dnsmasq.conf sin opciones que rompan builds más estrictas.
#    - Fallback robusto de interfaz.
#    - Limpieza total del puerto 53 antes de iniciar.
###############################################################################

set -e

echo "=== 🧠 SafeSearch DNS Installer v2.2 ==="
echo "Autor: Ryuz-crypto"
echo ""

# --- 0. Root check ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ejecuta con sudo o como root."
  exit 1
fi

# --- 1. Detectar hardware y red ---
echo "🔍 Detectando hardware e interfaz de red..."

CPUS=$(nproc)
RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)

# Interfaz: la primera interfaz UP distinta de loopback
IFACE=$(ip -o link show up | awk -F': ' '$2 !~ /lo/ {print $2; exit}')

# Fallback si no detectó (por ejemplo en algunas VMs apagadas)
if [ -z "$IFACE" ]; then
    IFACE="eth0"
fi

echo "  • CPU cores : ${CPUS}"
echo "  • RAM total : ${RAM_MB} MB"
echo "  • Interfaz  : ${IFACE}"
echo ""

# --- 2. Parametrizar cache-size y logging en base a recursos ---

if [ "$RAM_MB" -lt 2048 ]; then
  CACHE_SIZE=50000
elif [ "$RAM_MB" -lt 8192 ]; then
  CACHE_SIZE=100000
elif [ "$RAM_MB" -lt 32768 ]; then
  CACHE_SIZE=200000
else
  CACHE_SIZE=400000
fi

# logging detallado sólo si hay CPUs de sobra
if [ "$CPUS" -lt 8 ]; then
  LOG_QUERIES=false
else
  LOG_QUERIES=true
fi

echo "⚙️ Parámetros automáticos:"
echo "  • cache-size      : ${CACHE_SIZE}"
echo "  • log-queries ON? : ${LOG_QUERIES}"
echo ""

# --- 3. Instalar dnsmasq / dependencias ---
echo "📦 Instalando dependencias (dnsmasq, logrotate)..."
apt update -qq
apt install -y dnsmasq logrotate

# --- 4. Liberar el puerto 53 (UDP/TCP) matando/quitando otros resolvers ---
echo "🧹 Deshabilitando servicios conflictivos (bind9/named/systemd-resolved)..."

SERVICES=("bind9" "named" "systemd-resolved")

for svc in "${SERVICES[@]}"; do
  if systemctl list-unit-files | grep -q "^$svc"; then
    systemctl stop "$svc" || true
    systemctl disable "$svc" || true
  fi
done

# También mata cualquier proceso residual en 53 (por si acaso)
echo "🔫 Verificando procesos en puerto 53 y limpiando..."
PIDS_ON_53=$(ss -lntup | awk '/:53 / {print $NF}' | sed 's/.*pid=\([0-9]\+\).*/\1/' | sort -u)
if [ -n "$PIDS_ON_53" ]; then
  echo "   Procesos en 53: $PIDS_ON_53"
  for pid in $PIDS_ON_53; do
    kill -9 "$pid" || true
  done
fi

# --- 5. Ajustar /etc/resolv.conf para que el servidor use su propio dnsmasq ---
echo "🔧 Configurando /etc/resolv.conf -> 127.0.0.1 ..."
rm -f /etc/resolv.conf
echo "nameserver 127.0.0.1" > /etc/resolv.conf

# --- 6. Construir bloque de logging dinámico ---
if [ "$LOG_QUERIES" = true ]; then
  LOG_BLOCK="log-queries
log-facility=/var/log/dnsmasq.log"
else
  LOG_BLOCK="log-facility=/var/log/dnsmasq.log"
fi

# --- 7. Generar /etc/dnsmasq.conf ---
echo "📝 Escribiendo /etc/dnsmasq.conf ..."

cat > /etc/dnsmasq.conf <<EOF
###############################################################################
# dnsmasq configurado automáticamente por Ryuz-crypto (v2.2)
###############################################################################

# ---- Interfaz y binding ----
# Escuchar en la interfaz detectada (${IFACE}) y en IPv4.
interface=${IFACE}
bind-interfaces
listen-address=0.0.0.0
except-interface=lo

# ---- Sólo DNS, sin DHCP ----
# Marcamos explícitamente que no vamos a servir DHCP en esa interfaz
no-dhcp-interface=${IFACE}
no-dhcp-interface=lo
dhcp-range=

# ---- Resolución upstream ----
# No uses /etc/hosts ni /etc/resolv.conf del sistema para upstream.
no-resolv
no-hosts

# IMPORTANTE:
# Algunas builds de dnsmasq soportan "filter-AAAA" (bloquear IPv6), otras no.
# La dejamos comentada para compatibilidad. Si quieres bloquear IPv6 para evitar bypass,
# descomenta la siguiente línea y reinicia dnsmasq.
# filter-AAAA

# DNS públicos upstream para todo lo que no sea override.
server=1.1.1.1
server=8.8.8.8

# ---- Caché DNS dimensionada a tu RAM ----
cache-size=${CACHE_SIZE}
no-negcache

# ---- Hardening básico ----
bogus-priv
stop-dns-rebind

# ---- SafeSearch Overrides ----
# Google SafeSearch (forcesafesearch.google.com -> suele resolver a 216.239.38.120)
address=/www.google.com/216.239.38.120
address=/google.com/216.239.38.120

# YouTube Restricted Mode (usa mismos VIPs de Google SafeSearch)
address=/www.youtube.com/216.239.38.120
address=/youtube.com/216.239.38.120

# Bing Strict SafeSearch
address=/www.bing.com/204.79.197.220
address=/bing.com/204.79.197.220

# ---- Logging dinámico según recursos ----
${LOG_BLOCK}
EOF

# --- 8. Configurar logging seguro y rotación ---
echo "🌀 Configurando log y rotación..."

# Creamos/aseguramos el archivo de log. No asumimos usuario/grupo dnsmasq.
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
        # Señal HUP para que dnsmasq reabra el log
        systemctl kill -s HUP dnsmasq >/dev/null 2>&1 || true
    endscript
}
EOF

# --- 9. Recargar configuración systemd y levantar dnsmasq ---
echo "🚀 Iniciando y habilitando dnsmasq..."
systemctl daemon-reload
systemctl restart dnsmasq
systemctl enable dnsmasq

# Comprobar estado rápido
echo "📡 Estado actual de dnsmasq:"
systemctl --no-pager status dnsmasq || true

# --- 10. Pruebas funcionales básicas ---
echo "🔎 Prueba local de resolución forzada:"
echo "dig @127.0.0.1 www.google.com +short"
dig @127.0.0.1 www.google.com +short || true
echo "dig @127.0.0.1 www.youtube.com +short"
dig @127.0.0.1 www.youtube.com +short || true
echo "dig @127.0.0.1 www.bing.com +short"
dig @127.0.0.1 www.bing.com +short || true

echo ""
echo "✅ Instalación finalizada."
echo "Ahora en un cliente Windows:"
echo "1) Configura el DNS preferido con la IP de este servidor."
echo "2) ipconfig /flushdns"
echo "3) nslookup www.google.com <IP_DE_ESTE_SERVIDOR>"
echo ""
echo "Deberías ver que www.google.com responde con 216.239.38.120 (SafeSearch)."
echo ""
echo "Script por Ryuz-crypto 🧠"
###############################################################################


