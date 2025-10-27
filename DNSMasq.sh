#!/bin/bash
###############################################################################
#  SafeSearch DNS Installer (dnsmasq)
#  Autor: Ryuz-crypto
#  Versión: v2.4
#
#  Objetivo:
#    - Levantar dnsmasq como servidor DNS con SafeSearch obligatorio
#      (Google / YouTube / Bing) SIN servir DHCP.
#
#  Cambios v2.4:
#    - Se elimina por completo cualquier referencia a "dhcp-range="
#      y configuraciones DHCP que rompan dnsmasq --test.
#    - Configuración mínima y portable compatible con builds estrictas.
#    - Pre-chequeo con `dnsmasq --test` antes de arrancar el servicio.
###############################################################################

set -e

echo "=== 🧠 SafeSearch DNS Installer v2.4 ==="
echo "Autor: Ryuz-crypto"
echo ""

# --- 0. Root check ---
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ejecuta con sudo o como root."
  exit 1
fi

# --- 1. Detect hardware / interfaz ---
echo "🔍 Detectando hardware e interfaz de red..."

CPUS=$(nproc)
RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)

# Detecta la primera interfaz UP distinta de loopback
IFACE=$(ip -o link show up | awk -F': ' '$2 !~ /lo/ {print $2; exit}')
if [ -z "$IFACE" ]; then
    IFACE="eth0"
fi

echo "  • CPU cores : ${CPUS}"
echo "  • RAM total : ${RAM_MB} MB"
echo "  • Interfaz  : ${IFACE}"
echo ""

# --- 2. Parámetros dinámicos según recursos ---

# cache-size en función de la RAM
if [ "$RAM_MB" -lt 2048 ]; then
  CACHE_SIZE=50000
elif [ "$RAM_MB" -lt 8192 ]; then
  CACHE_SIZE=100000
elif [ "$RAM_MB" -lt 32768 ]; then
  CACHE_SIZE=200000
else
  CACHE_SIZE=400000
fi

# logging detallado solo si hay CPU suficiente
if [ "$CPUS" -lt 8 ]; then
  LOG_QUERIES=false
else
  LOG_QUERIES=true
fi

echo "⚙️ Parámetros automáticos:"
echo "  • cache-size      : ${CACHE_SIZE}"
echo "  • log-queries ON? : ${LOG_QUERIES}"
echo ""

# --- 3. Instalar dependencias básicas ---
echo "📦 Instalando dependencias (dnsmasq, logrotate)..."
apt update -qq
apt install -y dnsmasq logrotate

# --- 4. Liberar el puerto 53 (quitar resolvers que chocan) ---
echo "🧹 Deshabilitando servicios conflictivos (bind9/named/systemd-resolved)..."

SERVICES=("bind9" "named" "systemd-resolved")
for svc in "${SERVICES[@]}"; do
  if systemctl list-unit-files | grep -q "^$svc"; then
    systemctl stop "$svc" || true
    systemctl disable "$svc" || true
  fi
done

# Mata cualquier proceso que siga agarrando el puerto 53 TCP/UDP
echo "🔫 Verificando procesos en puerto 53 y limpiando..."
PIDS_ON_53=$(ss -lntup | awk '/:53 / {print $NF}' | sed 's/.*pid=\([0-9]\+\).*/\1/' | sort -u)
if [ -n "$PIDS_ON_53" ]; then
  echo "   Procesos en 53: $PIDS_ON_53"
  for pid in $PIDS_ON_53; do
    kill -9 "$pid" || true
  done
fi

# --- 5. Forzar que el propio servidor use dnsmasq ---
echo "🔧 Configurando /etc/resolv.conf -> 127.0.0.1 ..."
rm -f /etc/resolv.conf
echo "nameserver 127.0.0.1" > /etc/resolv.conf

# --- 6. Bloque de logging dinámico ---
if [ "$LOG_QUERIES" = true ]; then
  LOG_BLOCK="log-queries
log-facility=/var/log/dnsmasq.log"
else
  LOG_BLOCK="log-facility=/var/log/dnsmasq.log"
fi

# --- 7. Generar /etc/dnsmasq.conf sin DHCP y 100% compatible ---
echo "📝 Generando /etc/dnsmasq.conf ..."

cat > /etc/dnsmasq.conf <<EOF
###############################################################################
# dnsmasq configurado automáticamente por Ryuz-crypto (v2.4)
# Modo: Solo DNS (sin DHCP)
###############################################################################

# Interfaz en la que escuchamos peticiones DNS
interface=${IFACE}

# Atar el socket a la interfaz detectada (evitamos escuchar en todas)
bind-interfaces

# No usamos /etc/resolv.conf del sistema ni /etc/hosts como base
no-resolv
no-hosts

# Reenviadores DNS públicos (para todo lo que no forcemos)
server=1.1.1.1
server=8.8.8.8

# Caché tuneda según tu RAM
cache-size=${CACHE_SIZE}
no-negcache

# Hardening básico
bogus-priv
stop-dns-rebind

# --- SafeSearch Overrides ---
# Google SafeSearch (forcesafesearch.google.com ~ 216.239.38.120)
address=/www.google.com/216.239.38.120
address=/google.com/216.239.38.120

# YouTube Restricted Mode (mismo rango que Google SafeSearch)
address=/www.youtube.com/216.239.38.120
address=/youtube.com/216.239.38.120

# Bing Strict SafeSearch
address=/www.bing.com/204.79.197.220
address=/bing.com/204.79.197.220

# Logging dinámico
${LOG_BLOCK}
EOF

# --- 8. Configurar log y rotación ---
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

# --- 9. Validar config ANTES de iniciar el servicio ---
echo "🧪 Validando sintaxis con 'dnsmasq --test' ..."
if ! dnsmasq --test; then
    echo "❌ ERROR: La configuración de /etc/dnsmasq.conf falló la validación."
    echo "Revisa el mensaje de error de 'dnsmasq --test' arriba y corrige."
    exit 1
fi
echo "✅ Sintaxis OK."

# --- 10. Iniciar y habilitar dnsmasq ---
echo "🚀 Iniciando y habilitando dnsmasq..."
systemctl daemon-reload
systemctl restart dnsmasq
systemctl enable dnsmasq

echo "📡 Estado actual de dnsmasq:"
systemctl --no-pager status dnsmasq || true

# --- 11. Pruebas finales de resolución ---
echo "🔎 Prueba de resolución SafeSearch:"
echo "dig @127.0.0.1 www.google.com +short"
dig @127.0.0.1 www.google.com +short || true
echo "dig @127.0.0.1 www.youtube.com +short"
dig @127.0.0.1 www.youtube.com +short || true
echo "dig @127.0.0.1 www.bing.com +short"
dig @127.0.0.1 www.bing.com +short || true

echo ""
echo "✅ Instalación finalizada (v2.4)."
echo "Ahora en un cliente Windows:"
echo "1) Usa la IP de este servidor como DNS preferido."
echo "2) ipconfig /flushdns"
echo "3) nslookup www.google.com <IP_DE_ESTE_SERVIDOR>"
echo "Deberías ver 216.239.38.120 para www.google.com (SafeSearch forzado)."
echo ""
echo "Script por Ryuz-crypto 🧠"
###############################################################################
