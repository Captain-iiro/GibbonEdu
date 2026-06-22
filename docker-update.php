<?php
/**
 * Standalone CLI updater for Docker entrypoint.
 * Runs CHANGEDB.php SQL migrations when the database version is behind the code version.
 */

$configPath = __DIR__ . '/config.php';
$versionPath = __DIR__ . '/version.php';
$changedbPath = __DIR__ . '/CHANGEDB.php';

if (!file_exists($configPath)) {
    echo "config.php not found. Skipping update.\n";
    exit(0);
}

require $configPath;
require $versionPath;

$versionCode = $version ?? '0.0.00';

try {
    $dsn = "mysql:host={$databaseServer};dbname={$databaseName};charset=utf8";
    $pdo = new PDO($dsn, $databaseUsername, $databasePassword, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);
} catch (PDOException $e) {
    echo "Database connection failed: " . $e->getMessage() . "\n";
    exit(1);
}

// Get current DB version
$stmt = $pdo->query("SELECT value FROM gibbonSetting WHERE scope='System' AND name='version'");
$versionDB = $stmt->fetchColumn();

if ($versionDB === false) {
    echo "Could not read database version.\n";
    exit(1);
}

if (version_compare($versionCode, $versionDB) <= 0) {
    echo "Database is up to date ({$versionDB}).\n";
    exit(0);
}

echo "Database version: {$versionDB}\n";
echo "Code version: {$versionCode}\n";
echo "Update required. Running CHANGEDB.php migrations...\n";

if (!file_exists($changedbPath)) {
    echo "CHANGEDB.php not found.\n";
    exit(1);
}

require $changedbPath;

if (!isset($sql) || empty($sql)) {
    echo "No migrations found in CHANGEDB.php.\n";
    exit(0);
}

$errors = [];

foreach ($sql as $version) {
    if (version_compare($version[0], $versionDB, '>') && version_compare($version[0], $versionCode, '<=')) {
        echo "  Applying version {$version[0]}...\n";
        $tokens = explode(';end', $version[1]);
        foreach ($tokens as $token) {
            $token = trim($token);
            if (empty($token)) continue;
            try {
                $pdo->exec($token);
                echo "    OK: " . mb_substr($token, 0, 80) . "...\n";
            } catch (PDOException $e) {
                $msg = $e->getMessage();
                echo "    ERROR: {$msg}\n";
                $errors[] = "{$version[0]}: {$msg}";
            }
        }
        $versionDB = $version[0];
    }
}

// Update version in DB
$updateStmt = $pdo->prepare("UPDATE gibbonSetting SET value=:version WHERE scope='System' AND name='version'");
$updateStmt->execute(['version' => $versionCode]);

if (!empty($errors)) {
    echo "\nUpdate completed with " . count($errors) . " error(s).\n";
    foreach ($errors as $error) {
        echo "  - {$error}\n";
    }
    exit(1);
}

echo "\nUpdate complete. Version: {$versionCode}\n";
exit(0);
