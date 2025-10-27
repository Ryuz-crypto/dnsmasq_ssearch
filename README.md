Realiza la configuración de un servidor DNS en Ubuntu Server para SafeSearch exclusivamente, detecta CPU, RAM y HDD interfaz de acceso y parametriza de acuerdo a eso los logs de retención.

# 1 Instalar Git
sudo apt update && sudo apt install -y git

# 2 Clonar el repositorio
git clone https://github.com/Ryuz-crypto/dnsmasq_ssearch.git

# 3 Entrar al directorio
cd dnsmasq_ssearch

# 4 Corregir formato de Windows a Linux
sudo apt install -y dos2unix

# 5 Aplicarlo al archivo
sudo dos2unix DNSMasq.sh

# 6 Dar permisos al archivo
sudo chmod +x DNSMasq.sh

# 7 Ejecutarlo
sudo ./DNSMasq.sh

# Resumen:
sudo apt update && sudo apt install -y git

git clone https://github.com/Ryuz-crypto/dnsmasq_ssearch.git

cd dnsmasq_ssearch

sudo apt install -y dos2unix

sudo dos2unix DNSMasq.sh

sudo chmod +x DNSMasq.sh

sudo ./DNSMasq.sh








