<?php
// =====================================================================
// LA OBRA · SISTEMA VERSIÓN 2
// Exporta los datos de la versión 1 (MySQL "la_obra_db" en XAMPP) a un
// archivo .sql para PostgreSQL / Supabase.
//
// SOLO LEE la base de la versión 1: no modifica nada de lo que ya tienes.
//
// Cómo usarlo:
//   1. Copia este archivo a la carpeta del backend de la versión 1, junto a health.php:
//        C:\xampp\htdocs\la-obra-sistema\backend\exportar_mysql_a_supabase.php
//   2. Con Apache y MySQL encendidos, abre en el navegador de ESA computadora:
//        http://localhost/la-obra-sistema/backend/exportar_mysql_a_supabase.php
//   3. Descarga "datos" (y "fotos" si tienes fotos de productos o tickets).
//   4. En Supabase → SQL Editor, pega y ejecuta primero el archivo de datos
//      y después el de fotos (ver README, sección "Migrar los datos").
// =====================================================================

$local = in_array($_SERVER['REMOTE_ADDR'] ?? '', ['127.0.0.1', '::1'], true);
if (!$local) {
    http_response_code(403);
    exit('Abre esta página desde la computadora donde está XAMPP (http://localhost/...).');
}

ini_set('display_errors', '0');
ini_set('memory_limit', '512M');
set_time_limit(300);
date_default_timezone_set('America/Mexico_City');

// --- Conexión a la base de la versión 1 (usa la misma configuración del backend si existe)
$config = ['host' => 'localhost', 'port' => '3306', 'name' => 'la_obra_db', 'user' => 'root', 'pass' => ''];
foreach ([__DIR__ . '/config/database.local.php', __DIR__ . '/../config/database.local.php'] as $f) {
    if (is_file($f)) { $config = array_merge($config, require $f); break; }
}
foreach (['host' => 'DB_HOST', 'port' => 'DB_PORT', 'name' => 'DB_NAME', 'user' => 'DB_USER', 'pass' => 'DB_PASS'] as $k => $env) {
    if (getenv($env) !== false) $config[$k] = getenv($env);
}
// Carpeta de fotos de la versión 1 (backend/uploads)
$uploadsBase = is_dir(__DIR__ . '/uploads') ? __DIR__ : (is_dir(__DIR__ . '/../uploads') ? dirname(__DIR__) : __DIR__);

try {
    $pdo = new PDO("mysql:host={$config['host']};port={$config['port']};dbname={$config['name']};charset=utf8mb4", $config['user'], $config['pass']);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->exec("SET time_zone = '" . date('P') . "'");
} catch (Throwable $e) {
    header('Content-Type: text/plain; charset=utf-8');
    exit('No se pudo conectar a MySQL (' . $config['name'] . '): ' . $e->getMessage());
}

// Tablas de la versión 2, en orden de dependencias, con sus columnas.
// Solo se copian las columnas que existan en tu base de la versión 1.
$tables = [
    'users' => ['id', 'name', 'username', 'email', 'password_hash', 'status', 'role', 'must_change_password', 'created_at', 'updated_at'],
    'categories' => ['id', 'name', 'status'],
    'payment_methods' => ['id', 'name', 'status'],
    'inputs' => ['id', 'name', 'unit', 'package_type', 'package_quantity', 'package_content_unit', 'status', 'min_stock'],
    'preparations' => ['id', 'name', 'description', 'yield_quantity', 'yield_unit', 'yield_estimated', 'created_at', 'updated_at'],
    'preparation_inputs' => ['id', 'preparation_id', 'input_id', 'quantity', 'is_estimated'],
    'products' => ['id', 'name', 'description', 'category_id', 'type', 'price', 'is_available', 'status', 'image_path'],
    'recipes' => ['id', 'product_id', 'input_id', 'quantity'],
    'product_components' => ['id', 'product_id', 'input_id', 'preparation_id', 'quantity', 'is_estimated', 'delivery_mode'],
    'orders' => ['id', 'user_id', 'order_status', 'payment_status', 'delivery_status', 'delivery_mode', 'customer_name', 'total', 'created_at', 'confirmed_at', 'delivered_at', 'cancelled_at'],
    'order_items' => ['id', 'order_id', 'product_id', 'quantity', 'unit_price', 'subtotal', 'standard_unit_cost'],
    'payments' => ['id', 'order_id', 'payment_method_id', 'amount', 'cash_received', 'change_amount', 'paid_at'],
    'purchases' => ['id', 'purchase_date', 'supplier', 'buyer', 'ticket_path', 'payment_method_id', 'user_id', 'total', 'created_at', 'updated_at'],
    'purchase_items' => ['id', 'purchase_id', 'input_id', 'quantity', 'unit_cost', 'subtotal', 'content_per_package', 'content_unit', 'total_base_quantity'],
    'purchase_history' => ['id', 'purchase_id', 'changed_by', 'previous_data', 'new_data', 'change_reason', 'changed_at'],
    'expenses' => ['id', 'amount', 'reason', 'user_id', 'status', 'created_at', 'updated_at', 'cancelled_by', 'cancelled_at', 'cancellation_reason'],
    'expense_history' => ['id', 'expense_id', 'action', 'previous_data', 'new_data', 'change_reason', 'changed_by', 'changed_at'],
    'waste_records' => ['id', 'affected_type', 'input_id', 'product_id', 'preparation_id', 'quantity', 'is_approximate', 'waste_date', 'reason', 'classification', 'estimated_unit_cost', 'estimated_total_cost', 'cost_status', 'user_id', 'created_at'],
    'inventory_movements' => ['id', 'input_id', 'movement_type', 'quantity', 'unit_cost', 'reference_type', 'reference_id', 'note', 'user_id', 'created_at'],
    'order_test_invoices' => ['order_id', 'request_id', 'request_xml', 'stamped_xml', 'uuid'],
];
$booleans = ['must_change_password', 'yield_estimated', 'is_estimated', 'is_available', 'is_approximate'];
$nullableEnums = ['role'];

function existingColumns(PDO $pdo, string $table): array
{
    $s = $pdo->prepare('SELECT LOWER(COLUMN_NAME) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?');
    $s->execute([$table]);
    return $s->fetchAll(PDO::FETCH_COLUMN);
}

function pgValue($v, string $col, array $booleans, array $nullableEnums, string $table = ''): string
{
    if ($v === null) return 'null';
    if (in_array($col, $booleans, true)) return ((int)$v) ? 'true' : 'false';
    if (in_array($col, $nullableEnums, true) && $v === '') return 'null';
    // Fechas "0000-00-00" de MySQL: en PostgreSQL no existen
    if (is_string($v) && preg_match('/^0000-00-00/', $v)) {
        $required = in_array($col, ['created_at', 'paid_at', 'changed_at'], true) || ($table === 'users' && $col === 'updated_at');
        return $required ? 'la_obra_v2.now_mx()' : 'null';
    }
    return "'" . str_replace("'", "''", (string)$v) . "'";
}

// Leer todo
$summary = [];
$sql = [];
$missingFiles = 0;
$referenced = [];
foreach ($tables as $table => $cols) {
    $have = existingColumns($pdo, $table);
    if (!$have) { $summary[$table] = 'no existe en la versión 1 (se omite)'; continue; }
    $use = array_values(array_filter($cols, fn($c) => in_array($c, $have, true)));
    $rows = $pdo->query('SELECT `' . implode('`,`', $use) . "` FROM `$table`")->fetchAll(PDO::FETCH_ASSOC);
    $summary[$table] = count($rows) . ' registro(s)';
    if (!$rows) continue;
    foreach ($rows as &$r) {
        foreach (['image_path' => 'products', 'ticket_path' => 'tickets'] as $pathCol => $folder) {
            if (!empty($r[$pathCol])) {
                $file = $uploadsBase . '/' . ltrim($r[$pathCol], '/');
                if (preg_match('#^uploads/(products|tickets)/[A-Za-z0-9_.-]+$#', $r[$pathCol]) && is_file($file)) {
                    $referenced[$r[$pathCol]] = $file;
                } else {
                    $r[$pathCol] = null;   // la foto ya no existe en la carpeta uploads
                    $missingFiles++;
                }
            }
        }
    }
    unset($r);
    // Inserciones en bloques de 200 renglones
    foreach (array_chunk($rows, 200) as $chunk) {
        $values = array_map(function ($r) use ($use, $booleans, $nullableEnums, $table) {
            return '(' . implode(', ', array_map(fn($c) => pgValue($r[$c], $c, $booleans, $nullableEnums, $table), $use)) . ')';
        }, $chunk);
        $sql[] = "insert into la_obra_v2.$table (" . implode(', ', $use) . ") values\n" . implode(",\n", $values) . ";";
    }
}

$stamp = date('Y-m-d H:i');
$what = $_GET['download'] ?? '';

if ($what === 'datos') {
    header('Content-Type: application/sql; charset=utf-8');
    header('Content-Disposition: attachment; filename="la_obra_v2_datos_' . date('Ymd_Hi') . '.sql"');
    echo "-- La Obra · Sistema v2 — datos migrados desde MySQL '{$config['name']}' el $stamp\n";
    echo "-- Ejecutar en Supabase → SQL Editor DESPUÉS de instalar_todo.sql.\n";
    echo "-- ATENCIÓN: borra lo que haya en la_obra_v2 (por ejemplo, el admin de prueba) y lo reemplaza con estos datos.\n\n";
    echo "begin;\n\n";
    echo "truncate la_obra_v2.users, la_obra_v2.sessions, la_obra_v2.categories, la_obra_v2.payment_methods, la_obra_v2.inputs,\n";
    echo "  la_obra_v2.preparations, la_obra_v2.preparation_inputs, la_obra_v2.products, la_obra_v2.recipes, la_obra_v2.product_components,\n";
    echo "  la_obra_v2.orders, la_obra_v2.order_items, la_obra_v2.payments, la_obra_v2.purchases, la_obra_v2.purchase_items,\n";
    echo "  la_obra_v2.purchase_history, la_obra_v2.expenses, la_obra_v2.expense_history, la_obra_v2.waste_records,\n";
    echo "  la_obra_v2.inventory_movements, la_obra_v2.order_test_invoices restart identity cascade;\n\n";
    echo implode("\n\n", $sql), "\n\n";
    echo "-- Completar datos que la versión 1 calculaba en migrate.php\n";
    echo "update la_obra_v2.purchase_items set total_base_quantity = quantity * content_per_package where total_base_quantity is null;\n";
    echo "insert into la_obra_v2.inventory_movements(input_id, movement_type, quantity, unit_cost, reference_type, reference_id, note, user_id, created_at)\n";
    echo "select pi.input_id, 'purchase', pi.total_base_quantity, pi.subtotal / pi.total_base_quantity, 'purchase', p.id, 'Carga inicial', p.user_id, p.created_at\n";
    echo "from la_obra_v2.purchase_items pi join la_obra_v2.purchases p on p.id = pi.purchase_id\n";
    echo "where pi.total_base_quantity > 0 and not exists (select 1 from la_obra_v2.inventory_movements m\n";
    echo "  where m.reference_type = 'purchase' and m.reference_id = p.id and m.input_id = pi.input_id);\n\n";
    echo "-- Si la versión 1 no tenía métodos de pago, crear los básicos\n";
    echo "insert into la_obra_v2.payment_methods(name, status) select v.n, 'active' from (values ('Efectivo'), ('Transferencia'), ('Tarjeta')) v(n)\n";
    echo "where not exists (select 1 from la_obra_v2.payment_methods);\n\n";
    echo "select la_obra_v2.reset_sequences();\n\n";
    echo "commit;\n\n";
    echo "select 'Migración terminada: ' || (select count(*) from la_obra_v2.users) || ' usuarios, '\n";
    echo "  || (select count(*) from la_obra_v2.products) || ' productos, ' || (select count(*) from la_obra_v2.orders) || ' pedidos' as resultado;\n";
    exit;
}

if ($what === 'fotos') {
    header('Content-Type: application/sql; charset=utf-8');
    header('Content-Disposition: attachment; filename="la_obra_v2_fotos_' . date('Ymd_Hi') . '.sql"');
    echo "-- La Obra · Sistema v2 — fotos de productos y tickets ($stamp)\n";
    echo "-- Ejecutar en Supabase → SQL Editor DESPUÉS del archivo de datos.\n\n";
    $mimes = ['jpg' => 'image/jpeg', 'jpeg' => 'image/jpeg', 'png' => 'image/png', 'webp' => 'image/webp'];
    foreach ($referenced as $path => $file) {
        $ext = strtolower(pathinfo($file, PATHINFO_EXTENSION));
        $mime = $mimes[$ext] ?? 'image/jpeg';
        $bytes = file_get_contents($file);
        echo "insert into la_obra_v2.files(path, mime, data, size_bytes) values ('" . str_replace("'", "''", $path) . "', '$mime', decode('"
            . base64_encode($bytes) . "', 'base64'), " . strlen($bytes) . ") on conflict (path) do nothing;\n";
    }
    echo "\nselect count(*) || ' fotos en la base' as resultado from la_obra_v2.files;\n";
    exit;
}

$photoBytes = array_sum(array_map('filesize', $referenced));
?>
<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>Exportar a Supabase · La Obra v2</title>
<style>
body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#f5f5f2;color:#17181a;margin:0;padding:32px 16px}
main{max-width:720px;margin:0 auto;background:#fff;border:1px solid #e6e4de;border-radius:16px;padding:24px}
h1{margin:0 0 6px;font-size:22px}li{padding:5px 0;border-bottom:1px solid #f0efeb;font-size:14px;list-style:none}ul{padding:0}
a.btn{display:inline-block;margin:8px 8px 0 0;padding:10px 16px;border-radius:10px;background:#ffc526;color:#4a3600;font-weight:700;text-decoration:none}
.n{color:#6c7078;font-size:13px}.warn{background:#fff6d6;padding:10px 12px;border-radius:10px;font-size:14px}
</style></head><body><main>
<h1>Exportar datos a Supabase (versión 2)</h1>
<p class="n">Base de origen: <strong><?= htmlspecialchars($config['name']) ?></strong> · solo lectura, no se modifica nada.</p>
<ul>
<?php foreach ($summary as $t => $s): ?>
  <li><strong><?= htmlspecialchars($t) ?></strong>: <?= htmlspecialchars($s) ?></li>
<?php endforeach; ?>
  <li><strong>fotos</strong>: <?= count($referenced) ?> archivo(s), <?= number_format($photoBytes / 1048576, 1) ?> MB<?= $missingFiles ? " · $missingFiles referencia(s) a fotos que ya no existen (se dejan vacías)" : '' ?></li>
</ul>
<p>
  <a class="btn" href="?download=datos">1 · Descargar datos (.sql)</a>
  <?php if ($referenced): ?><a class="btn" href="?download=fotos">2 · Descargar fotos (.sql)</a><?php endif; ?>
</p>
<p class="warn">Al ejecutar el archivo de datos en Supabase se reemplaza lo que haya en el esquema <code>la_obra_v2</code>.
Las contraseñas se conservan: cada usuario entra con la misma que usaba en la versión 1.</p>
</main></body></html>
