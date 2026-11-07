<?php
declare(strict_types=1);
// Read-only constraint report for safe demo data planning. No inserts/updates; no credentials or personal data.
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
if ($db === '' || $user === '') { fwrite(STDERR, "ERROR: DB_NAME or DB_USER missing.\\n"); exit(1); }
try {
    $pdo = new PDO("mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4", $user, $pass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $tables = ['customers','merchants','products','loan_plans','leads','dimensions','site_faq','site_settings','loans','installments','orders','order_items','payments','wallet_transactions','stock_movements','settlements','journal_entries','journal_lines','fiscal_years'];
    echo "READ-ONLY TABLE CONSTRAINT REPORT\\n";
    foreach ($tables as $table) {
        $exists = $pdo->prepare("SHOW TABLES LIKE ?");
        $exists->execute([$table]);
        if (!$exists->fetchColumn()) continue;
        echo "\\n===== {$table} =====\\n";
        $row = $pdo->query("SHOW CREATE TABLE `" . str_replace("`", "``", $table) . "`")->fetch(PDO::FETCH_NUM);
        echo $row[1] . "\\n";
    }
    echo "\\nEND REPORT\\n";
} catch (Throwable $e) {
    $m = $e->getMessage();
    foreach ([$pass, $user, $db] as $secret) if ($secret !== '') $m = str_replace($secret, '[redacted]', $m);
    fwrite(STDERR, "ERROR: " . get_class($e) . ": " . $m . "\\n");
    exit(1);
}
