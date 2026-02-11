#!/usr/bin/env bash
set -euo pipefail
 
# --- CONFIG ---
DB_NAME="glpi"
DB_USER="glpiuser"
DB_PASS="${GLPI_DB_PASS:-$(openssl rand -base64 15)}"
ROOT_PASS="${MARIADB_ROOT_PASS:-$(openssl rand -base64 15)}"
GLPI_DIR="/var/www/html/glpi"
GLPI_PUBLIC="${GLPI_DIR}/public"
GLPI_FILES="/var/glpi_files"
APACHE_CONF="/etc/apache2/sites-available/glpi.conf"
 
export DEBIAN_FRONTEND=noninteractive
 
echo "=== Mise à jour des paquets ==="
apt update
apt upgrade -y
 
echo "=== Installation Apache, PHP et MariaDB + dépendances ==="
apt install -y apache2 mariadb-server mariadb-client \
    php php-cli libapache2-mod-php \
    php-mysql php-ldap php-apcu php-curl \
    php-gd php-mbstring php-xml php-intl php-zip php-bz2 php-bcmath \
    unzip wget curl ca-certificates lsb-release gnupg apt-transport-https \
    build-essential php-pear php-dev pkg-config
 
# --- Sécurisation MariaDB ---
echo "=== Sécurisation MariaDB ==="
mysql -u root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.user WHERE User='root' AND Host!='localhost';
FLUSH PRIVILEGES;
SQL
 
# --- Création DB et utilisateur GLPI ---
echo "=== Création base et utilisateur GLPI ==="
mysql -u root -p"${ROOT_PASS}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
 
# --- Télécharger et déployer GLPI ---
echo "=== Téléchargement de la dernière release GLPI ==="
LATEST_URL=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest \
  | grep browser_download_url | grep -E 'tgz|tar.gz' | cut -d '"' -f 4 | head -n1)
 
TMP_TGZ="/tmp/glpi.tgz"
wget -O "$TMP_TGZ" "$LATEST_URL"
tar -xzf "$TMP_TGZ" -C /tmp
 
rm -rf "$GLPI_DIR"
mv /tmp/glpi "$GLPI_DIR"
chown -R www-data:www-data "$GLPI_DIR"
chmod -R 755 "$GLPI_DIR"
 
# --- Créer le dossier files sécurisé hors web root ---
mkdir -p $GLPI_FILES
chown -R www-data:www-data $GLPI_FILES
chmod -R 750 $GLPI_FILES
 
# --- Config Apache ---
echo "=== Configuration Apache pour GLPI ==="
cat > "$APACHE_CONF" <<EOF
<VirtualHost *:80>
    ServerAdmin admin@example.com
    DocumentRoot $GLPI_PUBLIC
    ServerName glpi.local
 
    <Directory $GLPI_PUBLIC>
        AllowOverride All
        Require all granted
    </Directory>
 
    ErrorLog \${APACHE_LOG_DIR}/glpi_error.log
    CustomLog \${APACHE_LOG_DIR}/glpi_access.log combined
</VirtualHost>
EOF
 
cat > /var/www/html/glpi/public/.htaccess <<'EOF'
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^ index.php [QSA,L]
EOF
 
chown www-data:www-data /var/www/html/glpi/public/.htaccess
 
a2dissite 000-default.conf
a2ensite glpi.conf
a2enmod rewrite
systemctl restart apache2
 
# --- Afficher l'URL et informations ---
IP=$(hostname -I | awk '{print $1}')
echo "=================================================================="
echo "✅ GLPI installé avec succès !"
echo "Accédez à GLPI : http://$IP"
echo
echo "🔑 Identifiants MariaDB :"
echo " - root : $ROOT_PASS"
echo " - $DB_USER / $DB_PASS (base: $DB_NAME)"
echo
echo "📂 Dossier de données sécurisé : $GLPI_FILES"
echo "=================================================================="
 
# chmod +x install_glpi.sh