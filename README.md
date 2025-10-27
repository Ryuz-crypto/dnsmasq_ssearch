# 1. Instala git si no lo tienes
sudo apt update && sudo apt install -y git

# 2. Clona el repositorio
git clone https://github.com/Ryuz-crypto/dnsmasq_ssearch.git

# 3. Entra al directorio del proyecto
cd dnsmasq_ssearch

# 4. Asigna permisos de ejecución al script
sudo chmod +x DNSMasq.sh

# 5. Ejecuta el instalador con privilegios de root
sudo ./DNSMasq.sh
