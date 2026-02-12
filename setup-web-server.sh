#!/bin/bash
# =============================================================================
# setup-web-server.sh
# Projet : Infrastructure Proxmox Cluster avec SDN/NFV
# Auteurs : BERNARDIN Brice / DENA Killian  –  Février 2026
# Serveur : web-server-dmz  |  IP : 10.0.10.10  |  Zone : DMZ (vnet_dmz)
# Stack   : Debian 12 + Apache 2.4 + PHP 8.3
# =============================================================================
set -e

# ─── Couleurs ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}      $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC}    $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $1"; exit 1; }

[[ $EUID -ne 0 ]] && log_error "Exécuter en root : sudo bash $0"

echo -e "\n${BLUE}=== INSTALLATION SERVEUR WEB – kilbri / Zone DMZ ===${NC}\n"

# ──────────────────────────────────────────────────────────────────────────────
# ÉTAPE 1 : Configuration réseau
# ──────────────────────────────────────────────────────────────────────────────
log_info "ÉTAPE 1 : Configuration réseau"

IFACE="ens18"; IP="10.0.10.10"; MASK="255.255.255.0"
GW="10.0.10.1"; DNS="8.8.8.8 1.1.1.1"
HOST="web-server-dmz"; DOMAIN="kilbri.rt-iut.re"

hostnamectl set-hostname "$HOST"
cat > /etc/hosts <<EOF
127.0.0.1       localhost
127.0.1.1       ${HOST}.${DOMAIN} ${HOST}
${IP}           ${HOST}.${DOMAIN} ${HOST}
EOF

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto ${IFACE}
iface ${IFACE} inet static
    address ${IP}
    netmask ${MASK}
    gateway ${GW}
    dns-nameservers ${DNS}
EOF

systemctl restart networking || true
sleep 2
ping -c1 -W3 "$GW" &>/dev/null && log_success "Passerelle $GW joignable" \
  || log_warning "Passerelle $GW injoignable"

# ──────────────────────────────────────────────────────────────────────────────
# ÉTAPE 2 : Mise à jour système
# ──────────────────────────────────────────────────────────────────────────────
log_info "ÉTAPE 2 : Mise à jour du système"
apt update -y && apt upgrade -y
apt install -y curl wget gnupg2 lsb-release ca-certificates \
               apt-transport-https software-properties-common net-tools
log_success "Système à jour"

# ──────────────────────────────────────────────────────────────────────────────
# ÉTAPE 3 : Apache 2.4
# ──────────────────────────────────────────────────────────────────────────────
log_info "ÉTAPE 3 : Installation Apache 2.4"
apt install -y apache2
systemctl enable --now apache2
systemctl is-active --quiet apache2 || log_error "Apache n'a pas démarré"

a2enmod rewrite headers ssl expires deflate proxy proxy_fcgi
a2dissite 000-default.conf 2>/dev/null || true
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html
log_success "Apache 2.4 installé et modules activés"

# ──────────────────────────────────────────────────────────────────────────────
# ÉTAPE 4 : PHP 8.3 (dépôt Sury)
# ──────────────────────────────────────────────────────────────────────────────
log_info "ÉTAPE 4 : Installation PHP 8.3"
curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] \
https://packages.sury.org/php/ $(lsb_release -sc) main" \
  > /etc/apt/sources.list.d/php.list
apt update -y

apt install -y php8.3 php8.3-cli php8.3-fpm php8.3-mysql php8.3-curl \
               php8.3-gd php8.3-mbstring php8.3-xml php8.3-zip php8.3-intl \
               php8.3-bcmath php8.3-opcache libapache2-mod-php8.3

systemctl enable --now php8.3-fpm

# Durcissement php.ini
PHP_INI="/etc/php/8.3/apache2/php.ini"
sed -i 's/^expose_php = On/expose_php = Off/'               "$PHP_INI"
sed -i 's/^display_errors = On/display_errors = Off/'       "$PHP_INI"
sed -i 's/^;date.timezone =/date.timezone = Europe\/Paris/' "$PHP_INI"
sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI"
sed -i 's/^post_max_size = .*/post_max_size = 64M/'         "$PHP_INI"
sed -i 's/^memory_limit = .*/memory_limit = 256M/'          "$PHP_INI"
sed -i 's/^max_execution_time = .*/max_execution_time = 60/' "$PHP_INI"

a2enmod php8.3
log_success "PHP $(php -r 'echo PHP_VERSION;') installé et configuré"

# ──────────────────────────────────────────────────────────────────────────────
# ÉTAPE 5 : Virtual Host
# ──────────────────────────────────────────────────────────────────────────────
log_info "ÉTAPE 5 : Configuration Virtual Host"
SITE_DIR="/var/www/kilbri-web"
mkdir -p "$SITE_DIR"
chown -R www-data:www-data "$SITE_DIR"
chmod -R 755 "$SITE_DIR"

cat > /etc/apache2/sites-available/kilbri-web.conf <<VHEOF
<VirtualHost *:80>
    ServerName  web-server-dmz.${DOMAIN}
    ServerAlias ${IP}
    DocumentRoot /var/www/kilbri-web

    <Directory /var/www/kilbri-web>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog  \${APACHE_LOG_DIR}/kilbri-web-error.log
    CustomLog \${APACHE_LOG_DIR}/kilbri-web-access.log combined

    Header always set X-Frame-Options        "SAMEORIGIN"
    Header always set X-XSS-Protection       "1; mode=block"
    Header always set X-Content-Type-Options "nosniff"
    Header always set Referrer-Policy        "strict-origin-when-cross-origin"
</VirtualHost>
VHEOF

a2ensite kilbri-web.conf

# Page d'accueil
cat > "$SITE_DIR/index.php" <<'PHPEOF'
<?php $ip=$_SERVER['SERVER_ADDR']??'N/A'; ?>
<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8">
<title>kilbri – Serveur Web DMZ</title>
<style>body{font-family:Arial,sans-serif;background:#f4f4f4;max-width:800px;
margin:50px auto;padding:20px}.box{background:#fff;padding:30px;border-radius:10px;
box-shadow:0 2px 10px rgba(0,0,0,.1)}h1{color:#2c3e50}.ok{color:#27ae60;font-weight:bold}
.info{background:#ecf0f1;padding:15px;border-radius:5px;margin:20px 0}</style>
</head><body><div class="box">
<h1>🌐 Serveur Web – Zone DMZ</h1>
<p class="ok">✅ Serveur opérationnel !</p>
<div class="info">
  IP serveur : <?=htmlspecialchars($ip)?><br>
  Date       : <?=date('d/m/Y H:i:s')?><br>
  PHP        : <?=phpversion()?>
</div>
<h2>Projet kilbri – SDN/NFV</h2>
<p>Zone DMZ (10.0.10.0/24) – Proxmox + OPNsense + VXLAN</p>
</div></body></html>
PHPEOF
chown www-data:www-data "$SITE_DIR/index.php"
log_success "Virtual Host + page d'accueil créés"

# ──────────────────────────────────────────────────────────────────────────────
# ÉTAPE 6 : Sécurisation Apache
# ──────────────────────────────────────────────────────────────────────────────
log_info "ÉTAPE 6 : Sécurisation Apache"
SECCONF="/etc/apache2/conf-available/security.conf"
sed -i 's/^ServerTokens .*/ServerTokens Prod/'     "$SECCONF"
sed -i 's/^ServerSignature .*/ServerSignature Off/' "$SECCONF"
a2enconf security
log_success "ServerTokens Prod / ServerSignature Off"

# ──────────────────────────────────────────────────────────────────────────────
# ÉTAPE 7 : Fail2Ban
# ──────────────────────────────────────────────────────────────────────────────
log_info "ÉTAPE 7 : Installation Fail2Ban"
apt install -y fail2ban
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

cat >> /etc/fail2ban/jail.local <<'F2BEOF'

# ─── kilbri ──────────────────────────────────────────────
[apache-auth]
enabled = true
port    = http,https
logpath = /var/log/apache2/error.log

[apache-badbots]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/access.log
bantime  = 3600
maxretry = 3

[sshd]
enabled  = true
port     = ssh
maxretry = 5
bantime  = 3600
F2BEOF

systemctl enable --now fail2ban
systemctl is-active --quiet fail2ban && log_success "Fail2Ban actif" \
  || log_warning "Fail2Ban non démarré"

# ──────────────────────────────────────────────────────────────────────────────
# ÉTAPE 8 : Redémarrage final + tests
# ──────────────────────────────────────────────────────────────────────────────
log_info "ÉTAPE 8 : Redémarrage final"
systemctl restart apache2 php8.3-fpm

for svc in apache2 php8.3-fpm fail2ban; do
  systemctl is-active --quiet "$svc" && log_success "$svc actif" \
    || log_warning "$svc INACTIF !"
done

sleep 1
CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost)
[[ "$CODE" == "200" ]] && log_success "Page web HTTP 200 ✓" \
  || log_warning "Réponse HTTP : $CODE"

# ──────────────────────────────────────────────────────────────────────────────
# RÉSUMÉ
# ──────────────────────────────────────────────────────────────────────────────
echo -e "\n${GREEN}=== ✅ INSTALLATION TERMINÉE – SERVEUR WEB ===${NC}"
echo -e "  URL       : http://${IP}"
echo -e "  FQDN      : http://web-server-dmz.${DOMAIN}"
echo -e "  Webroot   : ${SITE_DIR}"
echo -e "  Logs      : /var/log/apache2/"
echo -e "  PHP       : $(php -r 'echo PHP_VERSION;')"
echo -e "\n${YELLOW}⚠  Post-install :${NC}"
echo "  → Test depuis PC-ENT : curl http://${IP}"
echo "  → Supprimer tout fichier phpinfo après vérification"
echo "  → Configurer SSL si nécessaire : a2enmod ssl"