#!/bin/bash

# =============================================================================
# LAMP Services Starter
# Coloca este archivo en el Escritorio y ejecútalo con doble clic
# (requiere que el archivo sea ejecutable: chmod +x iniciar_lamp.command)
# =============================================================================

# ── COLORES ───────────────────────────────────────────────────────────────────
RESET='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; WHITE='\033[0;37m'
BG_BLACK='\033[40m'; BG_BLUE='\033[44m'

log()  { echo -e "  ${GREEN}${BOLD}✔${RESET}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
err()  { echo -e "  ${RED}${BOLD}✘${RESET}  $1"; }

# ── ARQUITECTURA ──────────────────────────────────────────────────────────────
if [[ $(uname -m) == "arm64" ]]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

export PATH="$BREW_PREFIX/bin:$PATH"

# ── BANNER ────────────────────────────────────────────────────────────────────
clear
echo ""
echo -e "${BOLD}${BG_BLUE}${WHITE}                                          ${RESET}"
echo -e "${BOLD}${BG_BLUE}${WHITE}    🚀  LAMP Stack — Iniciar Servicios    ${RESET}"
echo -e "${BOLD}${BG_BLUE}${WHITE}                                          ${RESET}"
echo ""

# =============================================================================
# MYSQL
# =============================================================================
echo -e "  ${BOLD}${CYAN}MySQL${RESET}"
SVC=$(brew services list 2>/dev/null | grep "^mysql " | awk '{print $2}')
if [[ "$SVC" == "started" ]]; then
    warn "MySQL ya estaba corriendo"
else
    brew services start mysql &>/dev/null
    sleep 2
    SVC=$(brew services list 2>/dev/null | grep "^mysql " | awk '{print $2}')
    [[ "$SVC" == "started" ]] && log "MySQL iniciado" || err "MySQL no pudo iniciar"
fi

# =============================================================================
# APACHE
# =============================================================================
echo -e "  ${BOLD}${CYAN}Apache${RESET}"
SVC=$(brew services list 2>/dev/null | grep "^httpd " | awk '{print $2}')
if [[ "$SVC" == "started" ]]; then
    warn "Apache ya estaba corriendo"
else
    brew services start httpd &>/dev/null
    sleep 2
    SVC=$(brew services list 2>/dev/null | grep "^httpd " | awk '{print $2}')
    [[ "$SVC" == "started" ]] && log "Apache iniciado" || err "Apache no pudo iniciar"
fi

sleep 1

# =============================================================================
# VERIFICACIÓN
# =============================================================================
SVC_MYSQL=$(brew services list 2>/dev/null  | grep "^mysql " | awk '{print $2}')
SVC_APACHE=$(brew services list 2>/dev/null | grep "^httpd " | awk '{print $2}')
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null || echo "000")
PMA_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/phpmyadmin/ 2>/dev/null || echo "000")

# =============================================================================
# TICKET
# =============================================================================
svc_badge() {
    [[ "$1" == "started" ]] && echo "${GREEN}${BOLD} RUNNING ${RESET}" \
                             || echo "${RED}${BOLD} STOPPED ${RESET}"
}
url_badge() {
    [[ "$1" =~ ^(200|301|302)$ ]] && echo "${GREEN}${BOLD} OK $1  ${RESET}" \
                                   || echo "${RED}${BOLD} KO $1  ${RESET}"
}

echo ""
echo -e "${BOLD}${BG_BLACK}${WHITE}  +======================================+  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${CYAN}  |   LAMP Stack  ·  Estado de servicios  |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  |   $(date '+%d %b %Y  %H:%M:%S')                  |  ${RESET}"
echo -e "${BOLD}${BG_BLACK}${WHITE}  +--------------------------------------+  ${RESET}"
printf "${BOLD}${BG_BLACK}${WHITE}  |  🐬  MySQL   %b${BG_BLACK}${WHITE}                  |  ${RESET}\n" "$(svc_badge "$SVC_MYSQL")"
printf "${BOLD}${BG_BLACK}${WHITE}  |  🪶  Apache  %b${BG_BLACK}${WHITE}                  |  ${RESET}\n" "$(svc_badge "$SVC_APACHE")"
echo -e "${BOLD}${BG_BLACK}${WHITE}  +--------------------------------------+  ${RESET}"
printf "${BOLD}${BG_BLACK}${WHITE}  |  🌐  localhost:8080           %b${BG_BLACK}${WHITE}  |  ${RESET}\n" "$(url_badge "$HTTP_CODE")"
printf "${BOLD}${BG_BLACK}${WHITE}  |  🛠   localhost:8080/phpmyadmin %b${BG_BLACK}${WHITE}  |  ${RESET}\n" "$(url_badge "$PMA_CODE")"
echo -e "${BOLD}${BG_BLACK}${WHITE}  +======================================+  ${RESET}"
echo ""

# Abrir navegador si Apache responde
if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
    echo -e "  ${DIM}Abriendo navegador...${RESET}"
    sleep 1
    open "http://localhost:8080"
else
    echo -e "  ${YELLOW}⚠${RESET}  Apache no responde. Revisa los logs:"
    echo -e "  ${DIM}tail -f $BREW_PREFIX/var/log/httpd/error_log${RESET}"
fi

echo ""
echo -e "  ${DIM}Presiona Enter para cerrar...${RESET}"
read -r
