#!/bin/bash
# =============================================================================
# setup-db-server.sh
# Projet : Infrastructure Proxmox Cluster avec SDN/NFV
# Auteurs : BERNARDIN Brice / DENA Killian  –  Février 2026
# Serveur : db-server-dmz  |  IP : 10.0.10.20  |  Zone : DMZ (vnet_dmz)
# Stack   : Debian 12 + MariaDB 10.11
# =============================================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}      $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC}    $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $1"; exit 1; }

[[ $EUID -ne 0 ]] && log_error "Exécuter en root : sudo bash $0"

echo -e "\n${BLUE}=== INSTALLATION SERVEUR DB – kilbri / Zone DMZ ===${NC}\n"

# ──────────────────────────────────────────────────────────────────────────────
# ÉTAPE 1 : Configuration réseau
# ──────────────────────────────────────────────────────────────────────────────
log_info "ÉTAPE 1 : Configuration réseau"

IFACE="ens18"; IP="10.0.10.20"; MASK="255.255.255.0"
GW="10.0.10.1";  DNS="8.8.8.8 1.1.1.1"
HOST="db-server-dmz"; DOMAIN="kilbri.rt-iut.re"
WEB_IP="10.0.10.10"
ADMIN_NET="10.0.30.0/24"

hostnamectl set-hostname "$HOST"
cat > /etc/hosts <<EOF
127.0.0.1       localhost
127.0.1.1       ${HOST}.${DOMAIN} ${HOST}
${IP}           ${HOST}.${DOMAIN} ${HOST}
${WEB_IP}       web-server-dmz.${DOMAIN} web-server-dmz
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
               apt-transport-https net-tools ufw
log_success "Système à jour"

# ──────────────────────────────────────────────────────────────────────────────
# ÉTAPE 3 : Installation MariaDB 10.11
# ──────────────────────────────────────────────────────────────────────────────
log_info "ÉTAPE 3 : Installation MariaDB 10.11"
apt install -y mariadb-server mariadb-client
systemctl enable --now mariadb

systemctl is-active --quiet mariadb || log_error "MariaDB n'a pas démarré"
MARIADB_VER=$(mariadb --version | awk '{print $5}' | tr -d ',')
log_success "MariaDB installé : $MARIADB_VER"

# ──────────────────────────────────────────────────────────────────────────────
# ÉTAPE 4 : Sécurisation MariaDB
# ──────────────────────────────────────────────────────────────────────────────
log_info "ÉTAPE 4 : Sécurisation MariaDB"

ROOT_PASS="RootSecure@kilbri2026!"

mariadb -u root <<SQLEOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQLEOF
log_success "MariaDB sécurisé (root local uniquement, anonymes supprimés)"

# ──────────────────────────────────────────────────────────────────────────────
# ÉTAPE 5 : Création base de données et utilisateurs
# ──────────────────────────────────────────────────────────────────────────────
log_info "ÉTAPE 5 : Création base de données et utilisateurs"

DB_NAME="kilbri_webapp"
DB_USER="kilbri_user"
DB_PASS="MotDePasseFort123!"
ADMIN_USER="admin_db"
ADMIN_PASS="AdminPassSecure456!"

mariadb -u root -p"${ROOT_PASS}" <<SQLEOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME}
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${DB_USER}'@'${WEB_IP}'
  IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'${WEB_IP}';

CREATE USER IF NOT EXISTS '${ADMIN_USER}'@'10.0.30.%'
  IDENTIFIED BY '${ADMIN_PASS}';
GRANT ALL PRIVILEGES ON *.* TO '${ADMIN_USER}'@'10.0.30.%' WITH GRANT OPTION;

USE ${DB_NAME};
CREATE TABLE IF NOT EXISTS test_connexion (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  message    VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO test_connexion (message) VALUES
  ('Connexion MariaDB opérationnelle'),
  ('Projet kilbri SDN/NFV – Zone DMZ');

FLUSH PRIVILEGES;
SQLEOF
log_success "Base '$DB_NAME', utilisateurs '$DB_USER' et '$ADMIN_USER' créés"

# ──────────────────────────────────────────────────────────────────────────────
# ÉTAPE 6 : Configuration réseau MariaDB
# ──────────────────────────────────────────────────────────────────────────────
log_info "ÉTAPE 6 : Configuration réseau MariaDB"

MARIADB_CONF="/etc/mysql/mariadb.conf.d/50-server.cnf"
sed -i "s/^bind-address\s*=.*/bind-address = ${IP}/" "$MARIADB_CONF"
log_success "bind-address = ${IP}"

systemctl restart mariadb
sleep 2

ss -tlnp | grep -q ":3306" && log_success "Port 3306 ouvert sur ${IP}" \
  || log_warning "Port 3306 non détecté – vérifiez la config"

# ──────────────────────────────────────────────────────────────────────────────
# ÉTAPE 7 : Optimisation MariaDB
# ──────────────────────────────────────────────────────────────────────────────
log_info "ÉTAPE 7 : Optimisation MariaDB"

cat >> "$MARIADB_CONF" <<'INIEOF'

# ─── Optimisations kilbri ────────────────────────────────
[mysqld]
innodb_buffer_pool_size        = 1G
innodb_log_file_size           = 256M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method            = O_DIRECT
max_connections                = 200
connect_timeout                = 10
slow_query_log                 = 1
slow_query_log_file            = /var/log/mysql/mariadb-slow.log
long_query_time                = 2
character-set-server           = utf8mb4
collation-server               = utf8mb4_unicode_ci
INIEOF

systemctl restart mariadb
log_success "Optimisations MariaDB appliquées"

# ──────────────────────────────────────────────────────────────────────────────
# ÉTAPE 8 : Script de sauvegarde automatique
# ──────────────────────────────────────────────────────────────────────────────
log_info "ÉTAPE 8 : Configuration des sauvegardes automatiques"

BACKUP_DIR="/var/backups/mariadb"
BACKUP_SCRIPT="/usr/local/bin/backup-mariadb.sh"
mkdir -p "$BACKUP_DIR"
chmod 750 "$BACKUP_DIR"

cat > "$BACKUP_SCRIPT" <<BKEOF
#!/bin/bash
BACKUP_DIR="${BACKUP_DIR}"
DATE=\$(date +%Y%m%d_%H%M%S)
ROOT_PASS="${ROOT_PASS}"
mysqldump -u root -p"\${ROOT_PASS}" --all-databases \
  > "\${BACKUP_DIR}/backup_\${DATE}.sql"
gzip "\${BACKUP_DIR}/backup_\${DATE}.sql"
ls -t "\${BACKUP_DIR}"/backup_*.sql.gz | tail -n +8 | xargs -r rm
echo "[\$(date)] Backup OK : backup_\${DATE}.sql.gz" >> /var/log/mysql/backup.log
BKEOF

chmod 700 "$BACKUP_SCRIPT"
(crontab -l 2>/dev/null; echo "0 2 * * * ${BACKUP_SCRIPT} >> /var/log/mysql/backup.log 2>&1") \
  | crontab -
log_success "Script backup créé + cron quotidien à 02h00"

# ──────────────────────────────────────────────────────────────────────────────
# ÉTAPE 9 : Règles UFW
# ──────────────────────────────────────────────────────────────────────────────
log_info "ÉTAPE 9 : Configuration UFW"

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow from "$WEB_IP"    to any port 3306
ufw allow from 10.0.30.0/24 to any port 22
ufw allow from 10.0.30.0/24 to any port 3306
# ufw --force enable   # Décommenter si souhaité (hors règles OPNsense/NFV)
log_success "Règles UFW définies (non activées – gérées par OPNsense)"

# ──────────────────────────────────────────────────────────────────────────────
# VÉRIFICATIONS FINALES
# ──────────────────────────────────────────────────────────────────────────────
log_info "Vérifications finales..."

systemctl is-active --quiet mariadb && log_success "mariadb actif" \
  || log_warning "mariadb INACTIF !"

mariadb -u "$DB_USER" -p"$DB_PASS" -h "$IP" "$DB_NAME" \
  -e "SELECT COUNT(*) FROM test_connexion;" &>/dev/null \
  && log_success "Connexion '$DB_USER'@'$IP' → '$DB_NAME' : OK" \
  || log_warning "Test de connexion échoué – vérifiez les credentials"

# ──────────────────────────────────────────────────────────────────────────────
# RÉSUMÉ
# ──────────────────────────────────────────────────────────────────────────────
echo -e "\n${GREEN}=== ✅ INSTALLATION TERMINÉE – SERVEUR DB ===${NC}"
echo -e "  IP MariaDB : ${IP}:3306"
echo -e "  FQDN       : db-server-dmz.${DOMAIN}"
echo -e "  Base       : ${DB_NAME}"
echo -e "  User app   : ${DB_USER}@${WEB_IP}"
echo -e "  User admin : ${ADMIN_USER}@10.0.30.%"
echo -e "  Backups    : ${BACKUP_DIR}"
echo -e "\n${YELLOW}⚠  Post-install :${NC}"
echo "  → CHANGEZ les mots de passe par défaut !"
echo "  → Test depuis web-server : mysql -h ${IP} -u ${DB_USER} -p ${DB_NAME}"
echo "  → Adaptez innodb_buffer_pool_size à la RAM de la VM"