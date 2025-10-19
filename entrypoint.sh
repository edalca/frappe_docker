#!/bin/bash
set -e

SITE_NAME=${1:-devsite}
shift

# ðŸ‘‰ Argumentos esperados: app_name=git_url
declare -A APPS
for pair in "$@"; do
  name="${pair%%=*}"
  url="${pair#*=}"
  APPS["$name"]="$url"
done

# ðŸ“ Directorios y archivos base
WORKDIR="/workspace/frappe-bench"
SITE_PATH="$WORKDIR/sites/$SITE_NAME"
ENV_FILE="/workspace/.env"
INSTALL_LOG="/workspace/installer-apps.log"
APPS_SNAPSHOT="sites/apps-$(date +%F).txt"
LOG_SNAPSHOT="installer-apps-$(date +%F).log"

# ðŸŒ± Variables de entorno
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

DB_HOST="${DB_HOST:-mariadb}"
DB_PORT="${DB_PORT:-3306}"
MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-Fr@pp3_DB!2025$}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
REDIS_CACHE="${REDIS_CACHE:-redis-cache:6379}"
REDIS_QUEUE="${REDIS_QUEUE:-redis-queue:6379}"
FRAPPE_VERSION="${FRAPPE_VERSION:-develop}"
PYTHON_VERSION="${PYTHON_VERSION:-python3.11}"

# ðŸš€ Inicializar Bench si no existe
if [ ! -d "$WORKDIR" ]; then
  echo "ðŸ§± [bench-init] Inicializando entorno Bench..."
  bench init frappe-bench --skip-redis-config-generation --frappe-branch "$FRAPPE_VERSION" --python "$PYTHON_VERSION"
else
  echo "âœ… [bench-init] Ya existe: $WORKDIR â€” saltando init."
fi

cd "$WORKDIR"

# ðŸ—‚ï¸ Asegurar carpeta apps
[ -d "apps" ] || mkdir apps

echo "ðŸ§  [config] Registrando apps y configurando entorno global..."
ls -1 apps > sites/apps.txt
cp sites/apps.txt "$APPS_SNAPSHOT"

bench set-config -g db_host "$DB_HOST"
bench set-config -gp db_port "$DB_PORT"
bench set-config -g redis_cache "redis://$REDIS_CACHE"
bench set-config -g redis_queue "redis://$REDIS_QUEUE"
bench set-config -g redis_socketio "redis://$REDIS_QUEUE"
echo "âœ… [config] ConfiguraciÃ³n global aplicada."

# ðŸ“¦ Instalar apps desde Git si no estÃ¡n registradas
touch "$INSTALL_LOG"
cp "$INSTALL_LOG" "$LOG_SNAPSHOT"

for app in "${!APPS[@]}"; do
  [ "$app" = "frappe" ] && continue
  if grep -q "^.*$app -> ${APPS[$app]}$" "$INSTALL_LOG"; then
    echo "âœ… [log] '$app' ya fue instalada desde esa URL. Saltando get-app..."
    continue
  fi
  echo "ðŸ“¦ [bench] Instalando '$app' desde ${APPS[$app]}..."
  bench get-app --overwrite --branch develop "$app" "${APPS[$app]}"
  echo "$(date +"%F %T") | $app -> ${APPS[$app]}" >> "$INSTALL_LOG"
done

# ðŸŒ Crear sitio si no existe o validar su estado
if [ ! -d "$SITE_PATH" ]; then
  echo "ðŸŒ [site] Creando sitio '$SITE_NAME'..."
  bench new-site "$SITE_NAME" \
    --db-host "$DB_HOST" \
    --admin-password "$ADMIN_PASSWORD" \
    --mariadb-root-password "$MARIADB_ROOT_PASSWORD"

  for app in $(ls apps); do
    [ "$app" = "frappe" ] && continue
    echo "ðŸ”— [install-app] Instalando '$app' en el sitio..."
    bench --site "$SITE_NAME" install-app "$app"
  done
else
  if bench --site "$SITE_NAME" show-config > /dev/null 2>&1; then
    echo "âœ… [site] El sitio '$SITE_NAME' ya existe y estÃ¡ funcional."
  else
    echo "âš ï¸ [site] El directorio existe pero el sitio puede estar incompleto. Revisa manualmente."
  fi
fi

echo -e "\nðŸ“„ Apps registradas en installer-apps.log:\n"
cat "$INSTALL_LOG"

echo -e "\nðŸŸ¢ [listo] Setup completo para '$SITE_NAME'."
bench start &

sleep 5
