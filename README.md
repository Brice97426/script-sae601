# 🌐 Infrastructure Proxmox Cluster avec SDN/NFV
## Serveur Web & Base de Données – Zone DMZ

**Projet :** Infrastructure Proxmox Cluster avec SDN/NFV  
**Auteurs :** BERNARDIN Brice / DENA Killian  
**Date :** Février 2026  
**Domaine :** kilbri.rt-iut.re

---

## 📋 Vue d'ensemble

Ce dépôt contient les scripts d'installation et de configuration automatisée des serveurs de la zone DMZ du projet kilbri. L'infrastructure repose sur un cluster Proxmox avec SDN/NFV, OPNsense et VXLAN.

### Architecture LAMP/LEMP Stack

```
Zone DMZ (vnet_dmz – 10.0.10.0/24)
├── VM 110 – web-server-dmz (10.0.10.10)
│   ├── OS      : Debian 12 (Bookworm)
│   ├── Web     : Apache 2.4
│   ├── Lang    : PHP 8.3
│   └── Loc     : kilbri1
│
└── VM 111 – db-server-dmz (10.0.10.20)
    ├── OS      : Debian 12 (Bookworm)
    ├── SGBD    : MariaDB 10.11
    └── Loc     : kilbri2
```

---

## 📁 Contenu du dépôt

```
.
├── README.md                  ← Ce fichier
├── setup-web-server.sh        ← Script d'installation VM 110 (Apache + PHP)
└── setup-db-server.sh         ← Script d'installation VM 111 (MariaDB)
```

---

## 🚀 Utilisation

### Prérequis

- VM créée sur Proxmox (selon Phase 2 du projet)
- Debian 12 (Bookworm) installé avec SSH activé
- Accès root ou sudo sur chaque VM
- Connexion internet disponible (ou miroir local configuré)

### Sur le Serveur Web (VM 110 – 10.0.10.10)

```bash
# 1. Cloner le dépôt
git clone https://github.com/Brice97426/script-sae601.git
cd kilbri-infra

# 2. Rendre le script exécutable
chmod +x setup-web-server.sh

# 3. Lancer l'installation
sudo bash setup-web-server.sh
```

### Sur le Serveur DB (VM 111 – 10.0.10.20)

```bash
# 1. Cloner le dépôt
git clone https://github.com/Brice97426/script-sae601.git
cd script-sae601

# 2. Rendre le script exécutable
chmod +x setup-db-server.sh

# 3. Lancer l'installation
sudo bash setup-db-server.sh
```

---

## ⚙️ Ce que font les scripts

### `setup-web-server.sh`

| Étape | Action |
|-------|--------|
| 1 | Configuration réseau statique (IP, hostname, /etc/hosts) |
| 2 | Mise à jour système + outils de base |
| 3 | Installation Apache 2.4 + activation des modules |
| 4 | Installation PHP 8.3 via dépôt Sury + durcissement php.ini |
| 5 | Configuration Virtual Host + page d'accueil |
| 6 | Sécurisation Apache (ServerTokens, ServerSignature) |
| 7 | Installation et configuration Fail2Ban |
| 8 | Redémarrage des services + vérifications finales |

### `setup-db-server.sh`

| Étape | Action |
|-------|--------|
| 1 | Configuration réseau statique (IP, hostname, /etc/hosts) |
| 2 | Mise à jour système + outils de base |
| 3 | Installation MariaDB 10.11 |
| 4 | Sécurisation MariaDB (mysql_secure_installation automatisé) |
| 5 | Création base `kilbri_webapp` + utilisateurs applicatif et admin |
| 6 | Configuration réseau MariaDB (bind-address DMZ) |
| 7 | Optimisation des performances InnoDB |
| 8 | Script de sauvegarde automatique (cron 02h00) |
| 9 | Règles UFW (désactivées – gérées par OPNsense/NFV) |

---

## 🔐 Informations de connexion par défaut

> ⚠️ **Ces mots de passe doivent être changés avant toute mise en production !**

### MariaDB

| Compte | Hôte autorisé | Base |
|--------|--------------|------|
| `root` | `localhost` uniquement | toutes |
| `kilbri_user` | `10.0.10.10` (web-server) | `kilbri_webapp` |
| `admin_db` | `10.0.30.0/24` (réseau ADMIN) | toutes |

### Accès phpMyAdmin (optionnel)

```
URL         : http://10.0.10.10/phpmyadmin
Serveur DB  : 10.0.10.20
Utilisateur : kilbri_user
```

---

## ✅ Checklist de validation

### Serveur Web

- [ ] Debian 12 installé avec IP fixe `10.0.10.10`
- [ ] Apache 2.4 opérationnel
- [ ] PHP 8.3 installé et configuré
- [ ] Virtual Host `kilbri-web` actif
- [ ] Page accessible depuis PC-ENT et PC-ADMIN
- [ ] Modules Apache activés (rewrite, headers, ssl)
- [ ] Fail2Ban installé et configuré
- [ ] Logs disponibles dans `/var/log/apache2/`

### Serveur DB

- [ ] Debian 12 installé avec IP fixe `10.0.10.20`
- [ ] MariaDB 10.11 installé et actif
- [ ] Sécurisation `mysql_secure_installation` effectuée
- [ ] Base `kilbri_webapp` créée
- [ ] Utilisateur `kilbri_user` créé avec accès depuis `10.0.10.10`
- [ ] Connexion distante activée (`bind-address = 10.0.10.20`)
- [ ] Test de connexion depuis le serveur web réussi
- [ ] Script de backup configuré

---

## 🧪 Tests de connectivité

```bash
# Depuis PC-ENT (10.0.20.101) → Serveur Web
curl http://10.0.10.10
# Résultat attendu : page HTML ✅

# Depuis PC-ADMIN (10.0.30.50) → Serveur DB
mysql -h 10.0.10.20 -u admin_db -p
# Résultat attendu : connexion MariaDB ✅

# Depuis Serveur Web → Serveur DB
php -r "new PDO('mysql:host=10.0.10.20;dbname=kilbri_webapp', 'kilbri_user', 'MotDePasseFort123!');"
# Résultat attendu : pas d'erreur ✅
```

---

## 📚 Sources et Documentation

- [Apache HTTP Server 2.4](https://httpd.apache.org/docs/2.4/)
- [PHP Manuel officiel (FR)](https://www.php.net/manual/fr/)
- [MariaDB Knowledge Base](https://mariadb.com/kb/en/)
- [Dépôt Sury – PHP 8.3 pour Debian](https://packages.sury.org/php/)
- [Fail2Ban Documentation](https://www.fail2ban.org/wiki/index.php/Main_Page)

---

## 📄 Licence

Projet académique – IUT Réunion – RT  
Usage interne uniquement.
