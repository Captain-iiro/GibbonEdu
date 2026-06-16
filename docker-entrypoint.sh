#!/bin/sh
set -e

# Skip if config.php already exists (e.g., mounted volume or post-install)
if [ -f /var/www/html/config.php ] && [ -s /var/www/html/config.php ]; then
    echo "config.php already exists, skipping generation."
    exec "$@"
fi

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

# Only generate config.php if the database has been initialized (gibbonSetting table exists)
if php -r "
    try {
        \$pdo = new PDO('mysql:host=${DB_HOST};dbname=${DB_NAME};charset=utf8', '${DB_USER}', '${DB_PASS}');
        \$stmt = \$pdo->query('SHOW TABLES LIKE \\\"gibbonSetting\\\"');
        exit(\$stmt->rowCount() > 0 ? 0 : 1);
    } catch (Exception \$e) {
        exit(1);
    }
" 2>/dev/null; then
    echo "Database already initialized, generating config.php from environment variables."

    # Generate config.php from environment variables
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
else
    echo "Database not initialized yet (gibbonSetting table missing). Skipping config.php generation."
fi

# Ensure writable directories exist
mkdir -p /var/www/html/resources/templates/cache
mkdir -p /var/www/html/var
mkdir -p /var/www/html/uploads

chown -R www-data:www-data /var/www/html/resources/templates/cache /var/www/html/var /var/www/html/uploads

exec "$@"
