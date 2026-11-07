<?php
declare(strict_types=1);
// Read-only schema report: prints no credentials and reads no application rows.
$root = __DIR__ . '/digi-bile-pay';
if (!is_file($root . '/.env')) $root = __DIR__;
$envFile = $root . '/.env';
if (!is_file($envFile)) { fwrite(STDERR, "ERROR: .env not found. Run from /workspaces/shopbileir.\n"); exit(1); }
$env = [];
foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
    $line = trim($line);
    if ($line === '' || str_starts_with($line, '#') || !str_contains($line, '=')) continue;
    [$key, $value] = explode('=', $line, 2);
    $env[trim($key)] = trim(trim($value), " \t\n\r\0\x0B'\"");
}
$get = static fn(string $key, string $default = ''): string => $env[$key] ?? $default;
$host = $get('DB_HOST', '127.0.0.1');
$port = $get('DB_PORT', '3306');
$db = $get('DB_DATABASE');
$user = $get('DB_USERNAME');
$pass = $get('DB_PASSWORD');
if ($db === '' || $user === '') { fwrite(STDERR, "ERROR: DB_DATABASE or DB_USERNAME missing in .env.\n"); exit(1); }
try {
    $pdo = new PDO("mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4", $user, $pass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    echo "DATABASE SCHEMA ONLY (no rows, no credentials)\n";
    $tables = $pdo->query("SHOW FULL TABLES WHERE Table_type = 'BASE TABLE'")->fetchAll(PDO::FETCH_NUM);
    foreach ($tables as $t) {
        $table = $t[0];
        echo "\n## TABLE " . $table . "\n";
        $quoted = chr(96) . str_replace(chr(96), chr(96).chr(96), $table) . chr(96);
        foreach ($pdo->query("SHOW COLUMNS FROM {$quoted}") as $c) {
            echo implode(" | ", [$c['Field'], $c['Type'], $c['Null'], (string)($c['Default'] ?? 'NULL'), $c['Key'], $c['Extra']]) . "\n";
        }
        $stmt = $pdo->prepare("SELECT COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
            FROM information_schema.KEY_COLUMN_USAGE
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND REFERENCED_TABLE_NAME IS NOT NULL
            ORDER BY ORDINAL_POSITION");
        $stmt->execute([$table]);
        foreach ($stmt as $fk) echo "FK " . $fk['COLUMN_NAME'] . " -> " . $fk['REFERENCED_TABLE_NAME'] . "." . $fk['REFERENCED_COLUMN_NAME'] . "\n";
    }
    echo "\nEND SCHEMA REPORT\n";
} catch (Throwable $e) {
    fwrite(STDERR, "ERROR: schema inspection failed (" . get_class($e) . "). Check that MariaDB is running.\n");
    exit(1);
}
