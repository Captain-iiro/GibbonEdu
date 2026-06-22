#!/bin/sh
set -e

# Default values
GUID=${GIBBON_GUID:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "default-gibbon-guid")}
DB_HOST=${GIBBON_DATABASE_HOST:-db}
DB_NAME=${GIBBON_DATABASE_NAME:-gibbon}
DB_USER=${GIBBON_DATABASE_USER:-gibbon}
DB_PASS=${GIBBON_DATABASE_PASSWORD:-}
CACHING=${GIBBON_CACHING:-10}

# Escape single quotes for PHP strings
escape_sq() {
    echo "$1" | sed "s/'/\\\\'/g"
}

DB_HOST_E=$(escape_sq "$DB_HOST")
DB_NAME_E=$(escape_sq "$DB_NAME")
DB_USER_E=$(escape_sq "$DB_USER")
DB_PASS_E=$(escape_sq "$DB_PASS")
GUID_E=$(escape_sq "$GUID")

# Check if the database has been initialized (gibbonSetting table exists)
db_is_initialized() {
    php -r "
        try {
            \$pdo = new PDO('mysql:host=${DB_HOST};dbname=${DB_NAME};charset=utf8', '${DB_USER}', '${DB_PASS}');
            \$stmt = \$pdo->query('SHOW TABLES LIKE \\\"gibbonSetting\\\"');
            exit(\$stmt->rowCount() > 0 ? 0 : 1);
        } catch (Exception \$e) {
            exit(1);
        }
    " 2>/dev/null
}

# Wait for database to be ready (max 60s)
wait_for_db() {
    echo "Waiting for database connection..."
    for i in $(seq 1 30); do
        if db_is_initialized; then
            echo "Database is ready."
            return 0
        fi
        echo "  Attempt $i/30..."
        sleep 2
    done
    echo "WARNING: Database not ready after 60s. Continuing anyway."
    return 1
}

# Run the standalone updater if config.php and DB are ready
run_updater() {
    if [ -f /var/www/html/config.php ] && [ -s /var/www/html/config.php ] && db_is_initialized; then
        echo "Checking for pending database migrations..."
        php /var/www/html/docker-update.php
    fi
}

# Download i18n .mo files for the configured language if missing
download_i18n() {
    if [ -n "${GIBBON_LANGUAGE:-}" ]; then
        local lang_dir="/var/www/html/i18n/${GIBBON_LANGUAGE}/LC_MESSAGES"
        local mo_file="${lang_dir}/gibbon.mo"
        if [ ! -f "${mo_file}" ]; then
            echo "Downloading i18n files for ${GIBBON_LANGUAGE}..."
            mkdir -p "${lang_dir}"
            php -r "
                \$url = 'https://github.com/GibbonEdu/i18n/blob/main/${GIBBON_LANGUAGE}/LC_MESSAGES/gibbon.mo?raw=true';
                \$content = @file_get_contents(\$url);
                if (\$content !== false && strlen(\$content) > 100) {
                    file_put_contents('${mo_file}', \$content);
                    echo 'Downloaded gibbon.mo (' . strlen(\$content) . ' bytes)\n';
                    exit(0);
                }
                echo 'Failed to download gibbon.mo\n';
                exit(1);
            " 2>/dev/null || true
        else
            echo "i18n files for ${GIBBON_LANGUAGE} already present."
        fi
    fi
}

# Ensure writable directories exist
mkdir -p /var/www/html/resources/templates/cache
mkdir -p /var/www/html/var
mkdir -p /var/www/html/uploads

chown -R www-data:www-data /var/www/html/resources/templates/cache /var/www/html/var /var/www/html/uploads

# If config.php already exists, check if the database is actually ready
if [ -f /var/www/html/config.php ] && [ -s /var/www/html/config.php ]; then
    if db_is_initialized; then
        echo "config.php already exists, database is ready. Running post-deploy tasks..."
        run_updater
        download_i18n
        exec "$@"
    else
        echo "config.php exists but database is not initialized. Removing config.php to allow installer to proceed."
        rm /var/www/html/config.php
    fi
fi

# If config.php doesn't exist and database is ready, generate it from env vars
if ! [ -f /var/www/html/config.php ] && db_is_initialized; then
    echo "Database already initialized, generating config.php from environment variables."

    cat > /var/www/html/config.php <<EOF
<?php
/*
Gibbon: the flexible, open school platform
Copyright © 2010, Gibbon Foundation
Gibbon™, Gibbon Education Ltd. (Hong Kong)
*/

\$databaseServer = '${DB_HOST_E}';
\$databaseUsername = '${DB_USER_E}';
\$databasePassword = '${DB_PASS_E}';
\$databaseName = '${DB_NAME_E}';
\$guid = '${GUID_E}';
\$caching = ${CACHING};
\$allowImpersonateUser = [];
EOF

    run_updater
    download_i18n
fi

exec "$@"
