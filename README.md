# LAMP Stack en macOS con Homebrew

> Guía completa del proceso de instalación y configuración de MySQL, Apache, PHP y phpMyAdmin en macOS usando Homebrew.

---

## Índice

1. [Resumen del stack](#1-resumen-del-stack)
2. [Prerequisitos](#2-prerequisitos)
3. [Instalación](#3-instalación)
4. [Configuración de Apache](#4-configuración-de-apache)
5. [Configuración de PHP](#5-configuración-de-php)
6. [Configuración de MySQL](#6-configuración-de-mysql)
7. [Configuración de phpMyAdmin](#7-configuración-de-phpmyadmin)
8. [Problemas encontrados y soluciones](#8-problemas-encontrados-y-soluciones)
9. [Script de instalación automática](#9-script-de-instalación-automática)
10. [Comandos de referencia rápida](#10-comandos-de-referencia-rápida)

---

## 1. Resumen del stack

| Componente | Versión | Puerto | Acceso |
|---|---|---|---|
| Apache (httpd) | 2.4.x | **8080** | http://localhost:8080 |
| MySQL | 9.x | 3306 | CLI / phpMyAdmin |
| PHP | 8.3.x | — | Módulo Apache |
| phpMyAdmin | 5.x | — | http://localhost:8080/phpmyadmin |

> **Nota sobre el puerto:** Homebrew Apache está diseñado para correr en el puerto `8080` sin privilegios de root. El puerto `80` requiere `sudo`, lo que genera conflictos de permisos en los binarios. El puerto `8080` es la configuración correcta y estable.

---

## 2. Prerequisitos

- macOS con Apple Silicon (arm64) o Intel (x86_64)
- Conexión a internet
- Terminal con permisos de usuario estándar

El script detecta automáticamente la arquitectura:

```
Apple Silicon → /opt/homebrew
Intel         → /usr/local
```

---

## 3. Instalación

### Homebrew

Si no está instalado, el script lo instala de forma no interactiva:

```bash
NONINTERACTIVE=1 /bin/bash -c \
  "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Luego agrega brew al PATH en `~/.zprofile`:

```bash
# Apple Silicon
eval "$(/opt/homebrew/bin/brew shellenv)"

# Intel
eval "$(/usr/local/bin/brew shellenv)"
```

### Paquetes

```bash
brew update
brew install mysql
brew install httpd
brew install php
brew install phpmyadmin
```

---

## 4. Configuración de Apache

Archivo de configuración: `/opt/homebrew/etc/httpd/httpd.conf`

### Puerto

Apache de Homebrew viene configurado en `8080`. No se modifica — es el puerto correcto para correr sin sudo.

```apache
Listen 8080
```

### Módulos habilitados

```apache
LoadModule rewrite_module lib/httpd/modules/mod_rewrite.so
LoadModule deflate_module lib/httpd/modules/mod_deflate.so
LoadModule expires_module lib/httpd/modules/mod_expires.so
LoadModule php_module /opt/homebrew/opt/php/lib/httpd/modules/libphp.so
```

### Soporte PHP

```apache
<IfModule php_module>
    DirectoryIndex index.php index.html
</IfModule>
AddType application/x-httpd-php .php
```

### AllowOverride

```apache
AllowOverride All
```

### DocumentRoot (WebRoot)

```
/opt/homebrew/var/www/
```

### Iniciar servicio

```bash
brew services start httpd
brew services restart httpd
```

> ⚠️ **Sin sudo.** Usar `sudo brew services restart httpd` causa que Homebrew tome ownership de los binarios de Apache, lo que corrompe futuras actualizaciones.

---

## 5. Configuración de PHP

PHP se integra como módulo de Apache. Una vez instalado con `brew install php`, el módulo se carga en `httpd.conf` apuntando a:

```
/opt/homebrew/opt/php/lib/httpd/modules/libphp.so
```

No requiere configuración adicional para funcionar en entorno de desarrollo local.

---

## 6. Configuración de MySQL

### Iniciar servicio

```bash
brew services start mysql
```

### Clave inicial

La instalación de Homebrew deja MySQL con el usuario `root` **sin contraseña**. El script limpia la instalación sin asignar clave:

```sql
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root'
  AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
```

### Cambio de contraseña

El script solicita una nueva contraseña al final de la instalación. El comando correcto para MySQL 8+ es:

```sql
ALTER USER 'root'@'localhost' IDENTIFIED BY 'nueva_clave';
FLUSH PRIVILEGES;
```

> ⚠️ **No usar** `IDENTIFIED WITH mysql_native_password` — ese plugin está deshabilitado por defecto en MySQL 8+.

---

## 7. Configuración de phpMyAdmin

### Alias en Apache

Se agrega al final de `httpd.conf`:

```apache
Alias /phpmyadmin /opt/homebrew/share/phpmyadmin

<Directory "/opt/homebrew/share/phpmyadmin">
    Options SymLinksIfOwnerMatch
    DirectoryIndex index.php
    AllowOverride All
    Require all granted
</Directory>
```

### config.inc.php

Ubicación: `/opt/homebrew/share/phpmyadmin/config.inc.php`

```php
<?php
$cfg['blowfish_secret'] = 'SECRETO_ALEATORIO_32_CHARS';
$i = 0;
$i++;
$cfg['Servers'][$i]['auth_type']       = 'cookie';
$cfg['Servers'][$i]['host']            = '127.0.0.1';   // TCP, no socket
$cfg['Servers'][$i]['port']            = '3306';
$cfg['Servers'][$i]['connect_type']    = 'tcp';
$cfg['Servers'][$i]['compress']        = false;
$cfg['Servers'][$i]['AllowNoPassword'] = true;           // permite clave en blanco
$cfg['UploadDir']  = '';
$cfg['SaveDir']    = '';
$cfg['TempDir']    = '/opt/homebrew/share/phpmyadmin/tmp';
```

Puntos críticos:
- `host = 127.0.0.1` con `connect_type = tcp` — evita el error de conexión por socket que ocurre en instalaciones Homebrew
- `AllowNoPassword = true` — necesario mientras la clave de root sea en blanco

### Directorio tmp

```bash
mkdir -p /opt/homebrew/share/phpmyadmin/tmp
chmod 777 /opt/homebrew/share/phpmyadmin/tmp
```

---

## 8. Problemas encontrados y soluciones

### ❌ `No services available to control with brew services`

**Causa:** El script se ejecutaba con `sudo`, haciendo que `brew` corriera como `root`, el cual no tiene servicios registrados.

**Solución:** Ejecutar el script sin `sudo`. Internamente, si se detecta que corre como root, se relanza automáticamente como el usuario real:

```bash
if [[ $EUID -eq 0 ]]; then
    exec sudo -u "$SUDO_USER" bash "$0" "$@"
fi
```

---

### ❌ `ERR_CONNECTION_REFUSED` en `http://localhost`

**Causa:** El `sed` para cambiar el puerto de `8080` a `80` no funcionó correctamente (problema de espacios en el patrón). Apache seguía en `8080`.

**Solución:** Abandonar el puerto `80` y usar `8080` de forma nativa — es como Homebrew está diseñado. Se intentó un workaround con `pfctl` para redirigir `80 → 8080`, pero generó complejidad innecesaria. La solución final fue dejar Apache en `8080`.

```bash
# Acceso correcto
http://localhost:8080
http://localhost:8080/phpmyadmin
```

---

### ❌ Warning: `running through sudo, using user/* instead of gui/*`

**Causa:** `sudo brew services restart httpd` genera un warning de dominio.

**Solución:** No usar `sudo` para servicios de Homebrew. Solo httpd necesitaba `sudo` para puerto `80`, y al moverse a `8080` desaparece esa necesidad por completo.

---

### ❌ Warning: `httpd must be run as non-root to start at user login`

**Causa:** Al arrancar httpd con `sudo brew services`, Homebrew toma ownership de los binarios (`root:admin`), lo que corrompe el servicio.

**Solución:** Usar siempre `brew services restart httpd` sin sudo.

---

### ❌ phpMyAdmin no carga

**Causas identificadas:**

1. `host = localhost` intenta conexión por socket Unix → falla en Homebrew
2. `AllowNoPassword = false` con clave en blanco → rechaza el login

**Solución:**

```php
$cfg['Servers'][$i]['host']            = '127.0.0.1';  // forzar TCP
$cfg['Servers'][$i]['connect_type']    = 'tcp';
$cfg['Servers'][$i]['AllowNoPassword'] = true;
```

---

### ❌ Cambio de contraseña MySQL sin efecto

**Causa:** Se usaba `IDENTIFIED WITH mysql_native_password`, plugin deshabilitado en MySQL 8+. El error se silenciaba con `&>/dev/null`.

**Solución:**

```sql
-- ❌ Incorrecto en MySQL 8+
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'clave';

-- ✅ Correcto
ALTER USER 'root'@'localhost' IDENTIFIED BY 'clave';
FLUSH PRIVILEGES;
```

---

### ❌ Variable `$RES` en `install_pkg()` recibía texto basura

**Causa:** Las funciones `log()` y `warn()` dentro de `install_pkg()` escribían en stdout, mezclándose con el valor de retorno `"already"` / `"installed"` que se capturaba con `$()`.

**Solución:** Redirigir todo output visual a stderr:

```bash
install_pkg() {
    local pkg=$1
    if brew list "$pkg" &>/dev/null 2>&1; then
        warn "$pkg ya está instalado" >&2   # ← stderr
        echo "already"                       # ← stdout (el valor retornado)
    else
        brew install "$pkg" &>/dev/null &
        spinner $! "Instalando $pkg"
        log "$pkg instalado" >&2            # ← stderr
        echo "installed"                     # ← stdout
    fi
}
```

---

### ❌ Script se caía inesperadamente

**Causa:** `set -e` (exit on error) combinado con comandos que retornan código no-cero en situaciones normales (servicios ya corriendo, grep sin resultados, etc.).

**Solución:** Eliminar `set -e` y agregar `|| true` explícito donde corresponde:

```bash
brew services start mysql &>/dev/null || true
cp "$HTTPD_CONF" "${HTTPD_CONF}.bak" 2>/dev/null || true
```

---

## 9. Script de instalación automática

El script `install_lamp.sh` realiza toda la instalación sin intervención del usuario.

### Ejecución

```bash
chmod +x install_lamp.sh && ./install_lamp.sh
```

### Flujo del script

```
1. Detectar arquitectura (arm64 / x86_64)
2. Instalar / verificar Homebrew
3. Instalar mysql, httpd, php, phpmyadmin (si no están)
4. Configurar y arrancar MySQL
5. Configurar httpd.conf (módulos, PHP, phpMyAdmin alias)
6. Generar config.inc.php de phpMyAdmin
7. Crear index.php de prueba en WebRoot
8. Reiniciar servicios
9. Mostrar ticket visual con estado de cada componente
10. Solicitar nueva contraseña MySQL (opcional)
11. Mostrar credenciales finales
```

### Ticket de salida

```
+==================================================+
|    LAMP STACK  ·  REPORTE DE INSTALACION         |
|    07 May 2026  14:23:01  ·  Apple Silicon        |
+--------------------------------------------------+
|  COMPONENTES                       ESTADO        |
+--------------------------------------------------+
||  🍺  Homebrew     4.5.1            YA EXISTIA  ||
|  . . . . . . . . . . . . . . . . . . . . . . .   |
||  🐬  MySQL        v9.3.0           INSTALADO   ||
||  🪶  Apache       v2.4.67          YA EXISTIA  ||
||  🐘  PHP          v8.3.21          INSTALADO   ||
||  🛠   phpMyAdmin   5.2.2            YA EXISTIA  ||
+--------------------------------------------------+
|  SERVICIOS                         ESTADO        |
+--------------------------------------------------+
||  🐬  MySQL                          RUNNING    ||
||  🪶  Apache                         RUNNING    ||
+--------------------------------------------------+
|  URLS                              ESTADO        |
+--------------------------------------------------+
||  🌐  localhost:8080                 OK 200      ||
||  🌐  localhost:8080/phpmyadmin      OK 200      ||
+==================================================+
```

---

## 10. Comandos de referencia rápida

### Servicios

```bash
# Estado
brew services list

# Apache
brew services start httpd
brew services stop httpd
brew services restart httpd

# MySQL
brew services start mysql
brew services stop mysql
brew services restart mysql
```

### MySQL CLI

```bash
# Conectar (clave en blanco)
mysql -u root

# Conectar con clave
mysql -u root -p

# Cambiar contraseña
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'nueva_clave'; FLUSH PRIVILEGES;"
```

### Logs

```bash
# Apache error log
tail -f /opt/homebrew/var/log/httpd/error_log

# Apache access log
tail -f /opt/homebrew/var/log/httpd/access_log

# MySQL error log
tail -f /opt/homebrew/var/log/mysql/error.log
```

### Rutas importantes

| Recurso | Ruta |
|---|---|
| WebRoot | `/opt/homebrew/var/www/` |
| httpd.conf | `/opt/homebrew/etc/httpd/httpd.conf` |
| phpMyAdmin dir | `/opt/homebrew/share/phpmyadmin/` |
| phpMyAdmin config | `/opt/homebrew/share/phpmyadmin/config.inc.php` |
| Apache logs | `/opt/homebrew/var/log/httpd/` |
| PHP config | `/opt/homebrew/etc/php/8.x/php.ini` |

> Para Intel Mac reemplaza `/opt/homebrew` por `/usr/local` en todas las rutas.

---

*Generado el 07 May 2026 — macOS · Homebrew LAMP Stack*

---

## 11. Ejecución
```bash
# Ejecutar en la carpeta donde está el archivo install_lamp.sh
chmod +x install_lamp.sh && sudo ./install_lamp.sh 
```
