#!/bin/bash

# =============================================================================
# LAMP Stack Installer para macOS con Homebrew
# MySQL + Apache (httpd en 8080) + PHP + phpMyAdmin
# =============================================================================

# ── USUARIO REAL ──────────────────────────────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
    REAL_USER="${SUDO_USER:-$(logname 2>/dev/null)}"
    if [[ -z "$REAL_USER" || "$REAL_USER" == "root" ]]; then
        echo "  Ejecuta el script SIN sudo:  ./install_lamp.sh"
        exit 1
    fi
    exec sudo -u "$REAL_USER" bash "$0" "$@"
fi

# ── COLORES ───────────────────────────────────────────────────────────────────
RESET='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; WHITE='\033[0;37m'
BG_BLACK='\033[40m'; BG_BLUE='\033[44m'

# ── ESTADO COMPONENTES ────────────────────────────────────────────────────────
STATUS_BREW=""; STATUS_MYSQL=""; STATUS_APACHE=""; STATUS_PHP=""; STATUS_PMA=""
VERSION_MYSQL=""; VERSION_APACHE=""; VERSION_PHP=""; VERSION_PMA=""
MYSQL_ROOT_PASS=""

# ── HELPERS ───────────────────────────────────────────────────────────────────
log()  { echo -e "  ${GREEN}${BOLD}✔${RESET}  $1"; }
info() { echo -e "  ${CYAN}→${RESET}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
step() { echo -e "\n${BOLD}${BLUE}▸ $1${RESET}"; }

spinner() {
    local pid=$1 msg=$2 frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏') i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}%s${RESET}  ${DIM}%s...${RESET}" "${frames[$((i % 10))]}" "$msg"
        i=$((i+1)); sleep 0.08
    done
    printf "\r%-60s\r" " "
}

install_pkg() {
    local pkg=$1
    if brew list "$pkg" &>/dev/null 2>&1; then
        warn "$pkg ya está instalado" >&2; echo "already"
    else
        info "Instalando $pkg..." >&2
        brew install "$pkg" &>/dev/null & spinner $! "Instalando $pkg"
        log "$pkg instalado" >&2; echo "installed"
    fi
}

# ── BANNER ────────────────────────────────────────────────────────────────────
clear
echo ""
echo -e "${BOLD}${BG_BLUE}${WHITE}                                                    ${RESET}"
echo -e "${BOLD}${BG_BLUE}${WHITE}        🚀  LAMP Stack Installer para macOS         ${RESET}"
echo -e "${BOLD}${BG_BLUE}${WHITE}        MySQL · Apache :8080 · PHP · phpMyAdmin     ${RESET}"
echo -e "${BOLD}${BG_BLUE}${WHITE}                                                    ${RESET}"
echo ""

# ── ARQUITECTURA ──────────────────────────────────────────────────────────────
if [[ $(uname -m) == "arm64" ]]; then
    BREW_PREFIX="/opt/homebrew"; ARCH_LABEL="Apple Silicon (arm64)"
else
    BREW_PREFIX="/usr/local";    ARCH_LABEL="Intel (x86_64)"
fi

echo -e "  ${DIM}Arquitectura :${RESET} ${BOLD}$ARCH_LABEL${RESET}"
echo -e "  ${DIM}Brew prefix  :${RESET} ${BOLD}$BREW_PREFIX${RESET}"
echo -e "  ${DIM}Puerto Apache:${RESET} ${BOLD}8080${RESET}"
echo -e "  ${DIM}─────────────────────────────────────────────${RESET}"

# =============================================================================
# 1. HOMEBREW
# =============================================================================
step "Homebrew"
if ! command -v brew &>/dev/null; then
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" &>/dev/null &
    spinner $! "Instalando Homebrew"
    if [[ $(uname -m) == "arm64" ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> "$HOME/.zprofile"
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    STATUS_BREW="NEW"; log "Homebrew instalado"
else
    STATUS_BREW="OK"; log "Homebrew → $(brew --version | head -1)"
fi
brew update --quiet &>/dev/null & spinner $! "Actualizando índice"
log "Índice actualizado"

# =============================================================================
# 2. MYSQL
# =============================================================================
step "MySQL"
RES=$(install_pkg mysql)
VERSION_MYSQL=$(mysql --version 2>/dev/null | awk '{print $3}' | tr -d ',' || true)
[[ "$RES" == "installed" ]] && STATUS_MYSQL="NEW" || STATUS_MYSQL="OK"
log "Versión: $VERSION_MYSQL"

# Arrancar MySQL
if [[ "$(brew services list 2>/dev/null | grep "^mysql " | awk '{print $2}')" != "started" ]]; then
    brew services start mysql &>/dev/null || true; sleep 3
    log "Servicio MySQL iniciado"
else
    warn "MySQL ya estaba corriendo"
fi

# Limpiar instalación (sin cambiar password)
if mysql -u root -e "SELECT 1;" &>/dev/null 2>&1; then
    mysql -u root &>/dev/null 2>&1 <<'EOF' || true
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
EOF
    log "Seguridad MySQL configurada (clave en blanco)"
else
    warn "MySQL: ya tiene clave configurada, omitiendo"
fi

# =============================================================================
# 3. APACHE (httpd en puerto 8080, sin sudo)
# =============================================================================
step "Apache (httpd)"
RES=$(install_pkg httpd)
VERSION_APACHE=$(httpd -v 2>/dev/null | grep "Server version" | awk '{print $3}' | cut -d'/' -f2 || true)
[[ "$RES" == "installed" ]] && STATUS_APACHE="NEW" || STATUS_APACHE="OK"
log "Versión: $VERSION_APACHE"

HTTPD_CONF="$BREW_PREFIX/etc/httpd/httpd.conf"
PHP_MODULE_PATH="$BREW_PREFIX/opt/php/lib/httpd/modules/libphp.so"
WEBROOT="$BREW_PREFIX/var/www"

cp "$HTTPD_CONF" "${HTTPD_CONF}.bak" 2>/dev/null || true

# Asegurar puerto 8080
sed -i '' 's/^Listen[[:space:]]*[0-9]*/Listen 8080/' "$HTTPD_CONF" 2>/dev/null || true

# Módulos necesarios
sed -i '' 's/#LoadModule rewrite_module/LoadModule rewrite_module/' "$HTTPD_CONF" 2>/dev/null || true
sed -i '' 's/#LoadModule deflate_module/LoadModule deflate_module/' "$HTTPD_CONF" 2>/dev/null || true
sed -i '' 's/#LoadModule expires_module/LoadModule expires_module/' "$HTTPD_CONF" 2>/dev/null || true

# Módulo PHP
if ! grep -q "libphp.so" "$HTTPD_CONF"; then
    sed -i '' "/LoadModule rewrite_module/a\\
LoadModule php_module $PHP_MODULE_PATH
" "$HTTPD_CONF" 2>/dev/null || true
fi

# AllowOverride All
sed -i '' 's/AllowOverride None/AllowOverride All/g' "$HTTPD_CONF" 2>/dev/null || true

# Soporte PHP
if ! grep -q "application/x-httpd-php" "$HTTPD_CONF"; then
    cat >> "$HTTPD_CONF" <<'PHPCONF'

# --- PHP ---
<IfModule php_module>
    DirectoryIndex index.php index.html
</IfModule>
AddType application/x-httpd-php .php
PHPCONF
fi

log "httpd.conf configurado (puerto 8080)"

# =============================================================================
# 4. PHP
# =============================================================================
step "PHP"
RES=$(install_pkg php)
VERSION_PHP=$(php -r 'echo PHP_VERSION;' 2>/dev/null || true)
[[ "$RES" == "installed" ]] && STATUS_PHP="NEW" || STATUS_PHP="OK"
log "Versión: $VERSION_PHP"

# =============================================================================
# 5. phpMyAdmin
# =============================================================================
step "phpMyAdmin"
RES=$(install_pkg phpmyadmin)
VERSION_PMA=$(brew info phpmyadmin 2>/dev/null | head -1 | awk '{print $3}' || echo "n/a")
[[ "$RES" == "installed" ]] && STATUS_PMA="NEW" || STATUS_PMA="OK"

PMA_DIR="$BREW_PREFIX/share/phpmyadmin"
PMA_TMP="$PMA_DIR/tmp"
PMA_CONFIG="$PMA_DIR/config.inc.php"

mkdir -p "$PMA_TMP" && chmod 777 "$PMA_TMP" || true

# Alias en Apache
if ! grep -q "Alias /phpmyadmin" "$HTTPD_CONF"; then
    cat >> "$HTTPD_CONF" <<PMACONF

# --- phpMyAdmin ---
Alias /phpmyadmin $PMA_DIR
<Directory "$PMA_DIR">
    Options SymLinksIfOwnerMatch
    DirectoryIndex index.php
    AllowOverride All
    Require all granted
</Directory>
PMACONF
fi

# config.inc.php
SECRET=$(openssl rand -base64 48 | tr -d '=+/\n' | cut -c1-32)
cat > "$PMA_CONFIG" <<PMAINI
<?php
\$cfg['blowfish_secret'] = '$SECRET';
\$i = 0;
\$i++;
\$cfg['Servers'][\$i]['auth_type']       = 'cookie';
\$cfg['Servers'][\$i]['host']            = '127.0.0.1';
\$cfg['Servers'][\$i]['port']            = '3306';
\$cfg['Servers'][\$i]['connect_type']    = 'tcp';
\$cfg['Servers'][\$i]['compress']        = false;
\$cfg['Servers'][\$i]['AllowNoPassword'] = true;
\$cfg['UploadDir']  = '';
\$cfg['SaveDir']    = '';
\$cfg['TempDir']    = '$PMA_TMP';
PMAINI

log "phpMyAdmin configurado"

# =============================================================================
# 6. PÁGINA DE PRUEBA
# =============================================================================
step "Página de prueba"
mkdir -p "$WEBROOT"
cat > "$WEBROOT/index.php" <<'PHPTEST'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8"><title>LAMP Stack OK</title>
    <style>
        *{box-sizing:border-box;margin:0;padding:0}
        body{font-family:-apple-system,sans-serif;background:#0f172a;
             display:flex;align-items:center;justify-content:center;min-height:100vh}
        .card{background:#1e293b;border-radius:16px;padding:40px 50px;text-align:center;
              box-shadow:0 20px 60px rgba(0,0,0,.5);border:1px solid #334155;
              max-width:420px;width:90%}
        h1{color:#f8fafc;font-size:1.6rem;margin-bottom:8px}
        .sub{color:#94a3b8;margin-bottom:28px;font-size:.9rem}
        .badge{display:inline-block;background:#0f172a;border:1px solid #334155;
               border-radius:8px;padding:6px 14px;margin:4px;
               font-size:.8rem;color:#38bdf8;font-family:monospace}
        .btn{display:inline-block;margin-top:24px;background:#3b82f6;color:white;
             text-decoration:none;padding:10px 24px;border-radius:8px;font-size:.9rem;font-weight:600}
    </style>
</head>
<body>
    <div class="card">
        <h1>✅ LAMP Stack activo</h1>
        <p class="sub">Todos los servicios funcionando</p>
        <span class="badge">PHP <?= PHP_VERSION ?></span>
        <span class="badge">Apache :8080</span>
        <span class="badge">MySQL</span>
        <br>
        <a class="btn" href="/phpmyadmin">→ phpMyAdmin</a>
    </div>
</body>
</html>
PHPTEST
log "index.php creado en $WEBROOT"

# =============================================================================
# 7. INICIAR SERVICIOS
# =============================================================================
step "Iniciando servicios"

brew services restart mysql &>/dev/null & spinner $! "Reiniciando MySQL"
log "MySQL → restarted"

brew services restart httpd &>/dev/null & spinner $! "Reiniciando Apache"
log "Apache → restarted"

sleep 3

# =============================================================================
# 8. VERIFICACIÓN
# =============================================================================
SVC_MYSQL=$(brew services list 2>/dev/null  | grep "^mysql " | awk '{print $2}' || echo "unknown")
SVC_APACHE=$(brew services list 2>/dev/null | grep "^httpd " | awk '{print $2}' || echo "unknown")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null || echo "000")
PMA_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/phpmyadmin/ 2>/dev/null || echo "000")

# =============================================================================
# 🎫  TICKET FINAL
# =============================================================================
ticket_row() {
    local emoji="$1" label="$2" version="$3" is_new="$4" badge
    [[ "$is_new" == "NEW" ]] && badge="${GREEN}${BOLD} INSTALADO ${RESET}" \
                              || badge="${CYAN}${BOLD} YA EXISTIA${RESET}"
    printf "${BOLD}${BG_BLACK}${WHITE}  ||  %s  %-12s  ${DIM}%-16s${RESET}${BOLD}${BG_BLACK}  %b${BG_BLACK}${WHITE}  ||${RESET}\n" \
        "$emoji" "$label" "$version" "$badge"
}
ticket_svc() {
    local emoji="$1" label="$2" status="$3" badge
    [[ "$status" == "started" ]] && badge="${GREEN}${BOLD} RUNNING ${RESET}" \
                                  || badge="${RED}${BOLD} STOPPED ${RESET}"
    printf "${BOLD}${BG_BLACK}${WHITE}  ||  %s  %-24s  %b${BG_BLACK}${WHITE}           ||${RESET}\n" \
        "$emoji" "$label" "$badge"
}
ticket_url() {
    local label="$1" code="$2" badge
    [[ "$code" =~ ^(200|301|302)$ ]] && badge="${GREEN}${BOLD} OK $code ${RESET}" \
                                      || badge="${RED}${BOLD} KO $code ${RESET}"
    printf "${BOLD}${BG_BLACK}${WHITE}  ||  🌐  %-28s  %b${BG_BLACK}${WHITE}       ||${RESET}\n" \
        "$label" "$badge"
}

echo ""
echo -e "${BOLD}${BG_BLACK}${WHITE}  +==================================================+  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${CYAN}  |    LAMP STACK  ·  REPORTE DE INSTALACION         |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  |    $(date '+%d %b %Y  %H:%M:%S')  ·  $ARCH_LABEL      |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  +--------------------------------------------------+  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  |  COMPONENTES                       ESTADO        |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  +--------------------------------------------------+  ${RESET}"
ticket_row "🍺" "Homebrew"   "$(brew --version 2>/dev/null | head -1 | awk '{print $2}')" "$STATUS_BREW"
echo -e "${BOLD}${BG_BLACK}${DIM}  |  . . . . . . . . . . . . . . . . . . . . . . .   |  ${RESET}"
ticket_row "🐬" "MySQL"      "v$VERSION_MYSQL"  "$STATUS_MYSQL"
ticket_row "🪶" "Apache"     "v$VERSION_APACHE" "$STATUS_APACHE"
ticket_row "🐘" "PHP"        "v$VERSION_PHP"    "$STATUS_PHP"
ticket_row "🛠 " "phpMyAdmin" "$VERSION_PMA"     "$STATUS_PMA"
echo -e "${BOLD}${BG_BLACK}${WHITE}  +--------------------------------------------------+  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  |  SERVICIOS                         ESTADO        |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  +--------------------------------------------------+  ${RESET}"
ticket_svc "🐬" "MySQL"  "$SVC_MYSQL"
ticket_svc "🪶" "Apache" "$SVC_APACHE"
echo -e "${BOLD}${BG_BLACK}${WHITE}  +--------------------------------------------------+  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  |  URLS                              ESTADO        |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  +--------------------------------------------------+  ${RESET}"
ticket_url "localhost:8080"            "$HTTP_CODE"
ticket_url "localhost:8080/phpmyadmin" "$PMA_CODE"
echo -e "${BOLD}${BG_BLACK}${WHITE}  +--------------------------------------------------+  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  |  ACCESO                                          |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  +--------------------------------------------------+  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${CYAN}  |   http://localhost:8080                          |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${CYAN}  |   http://localhost:8080/phpmyadmin              |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  |   Usuario MySQL  : ${YELLOW}root${WHITE}                       |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  |   Password MySQL : ${YELLOW}(en blanco)${WHITE}                |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  |   WebRoot        : ${DIM}$WEBROOT${WHITE}  |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  +--------------------------------------------------+  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  |  COMANDOS UTILES                                 |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  +--------------------------------------------------+  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${DIM}  |  brew services restart httpd                     |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${DIM}  |  brew services restart mysql                     |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${DIM}  |  brew services list                              |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${DIM}  |  tail -f $BREW_PREFIX/var/log/httpd/error_log    |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  +==================================================+  ${RESET}"
echo ""

# =============================================================================
# CAMBIO DE CLAVE MYSQL (interactivo al final)
# =============================================================================
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}${CYAN}  🔐  Cambio de contraseña MySQL                   ${RESET}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  Clave actual: ${YELLOW}${BOLD}(en blanco)${RESET}  — deja vacío para mantenerla"
echo ""

while true; do
    printf "  Nueva contraseña : "; read -rs NEW_PASS; echo ""
    if [[ -z "$NEW_PASS" ]]; then
        warn "Sin cambios — clave sigue en blanco"; break
    fi
    printf "  Confirmar        : "; read -rs NEW_PASS2; echo ""
    if [[ "$NEW_PASS" != "$NEW_PASS2" ]]; then
        echo -e "  ${RED}✘${RESET}  No coinciden, intenta de nuevo."; echo ""; continue
    fi
    if mysql -u root -e "SELECT 1;" &>/dev/null 2>&1; then
        # Usar variable de entorno para evitar problemas con caracteres especiales
        MYSQL_PWD="" mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${NEW_PASS}'; FLUSH PRIVILEGES;" 2>/tmp/mysql_err || true
        if [[ $? -eq 0 ]] || ! grep -q "ERROR" /tmp/mysql_err 2>/dev/null; then
            log "Contraseña actualizada"
            MYSQL_ROOT_PASS="$NEW_PASS"
        else
            warn "Error al cambiar clave: $(cat /tmp/mysql_err 2>/dev/null)"
        fi
    else
        warn "No se pudo conectar a MySQL sin clave"
    fi
    break
done

DISPLAY_PASS="${MYSQL_ROOT_PASS:-"(en blanco)"}"
echo ""
echo -e "${BOLD}${BG_BLACK}${WHITE}  +==================================================+  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  |  CREDENCIALES FINALES                            |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  +==================================================+  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${CYAN}  |   http://localhost:8080                          |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${CYAN}  |   http://localhost:8080/phpmyadmin              |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  |   Usuario  : ${YELLOW}root${WHITE}                               |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  |   Password : ${YELLOW}${DISPLAY_PASS}${WHITE}$(printf '%*s' $((25-${#DISPLAY_PASS})) '')  |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  +==================================================+  ${RESET}"
echo ""
