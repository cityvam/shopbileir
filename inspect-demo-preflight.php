<?php
declare(strict_types=1);
// Read-only demo-seed preflight. Never prints credentials or personal data.
$root = __DIR__ . '/digi-bile-pay';
if (!is_file($root . '/.env')) $root = __DIR__;
$env = [];
foreach (file($root . '/.env', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
    $line = trim($line);
    if ($line === '' || str_starts_with($line, '#') || !str_contains($line, '=')) continue;
    [$k, $v] = explode('=', $line, 2);
    $env[trim($k)] = trim(trim($v), " \\t\\n\\r\\0\\x0B'\"");
}
$host = $env['DB_HOST'] ?? '127.0.0.1';
$port = $env['DB_PORT'] ?? '3306';
$db = $env['DB_NAME'] ?? '';
$user = $env['DB_USER'] ?? '';
$pass = $env['DB_PASS'] ?? '';
if ($db === '' || $user === '') { fwrite(STDERR, "ERROR: DB_NAME or DB_USER missing.\n"); exit(1); }
try {
    $pdo = new PDO("mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4", $user, $pass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    echo "READ-ONLY DEMO PREFLIGHT (no inserts/updates; no personal data)\n";
    $tables = $pdo->query("SHOW FULL TABLES WHERE Table_type='BASE TABLE'")->fetchAll(PDO::FETCH_COLUMN);
    foreach ($tables as $table) {
        $q = $pdo->quote($table);
        $count = (int)$pdo->query("SELECT COUNT(*) FROM `" . str_replace("`", "``", $table) . "`")->fetchColumn();
        echo $table . ": " . $count . "\n";
    }
    echo "\nCOMPANIES (IDs/status only)\n";
    foreach ($pdo->query("SELECT id, status FROM companies ORDER BY id") as $r) {
        $id = (int)$r['id'];
        $users = $pdo->prepare("SELECT COUNT(*) FROM users WHERE company_id=?");
        $users->execute([$id]);
        $customers = $pdo->prepare("SELECT COUNT(*) FROM customers WHERE company_id=?");
        $customers->execute([$id]);
        echo "company_id={$id}; status={$r['status']}; users=" . (int)$users->fetchColumn() . "; customers=" . (int)$customers->fetchColumn() . "\n";
    }
    echo "\nEND PREFLIGHT\n";
} catch (Throwable $e) {
    $m = $e->getMessage();
    foreach ([$pass, $user, $db] as $secret) if ($secret !== '') $m = str_replace($secret, '[redacted]', $m);
    fwrite(STDERR, "ERROR: " . get_class($e) . ": " . $m . "\n");
    exit(1);
}
