<?php
// Pasa los datos de La Obra (XAMPP / MySQL la_obra_db) a Supabase (PostgreSQL, esquema la_obra_v2).
//
// Cómo usarlo (en la computadora donde está XAMPP):
//   1. Copia este archivo a C:\xampp\htdocs\la-obra-sistema\backend\exportar_mysql_a_supabase.php
//   2. Con Apache y MySQL encendidos abre:  http://localhost/la-obra-sistema/backend/exportar_mysql_a_supabase.php
//   3. Descarga "1 · Datos" y, si tienes fotos, "2 · Fotos".
//   4. En Supabase → SQL Editor → New query: pega el de datos → Run. Luego el de fotos → Run.
//
// Solo LEE la base de MySQL; no cambia nada. Solo funciona desde la misma computadora (localhost).
// No subas los archivos generados a GitHub: tienen información real del negocio.

if (!in_array($_SERVER['REMOTE_ADDR'] ?? '', ['127.0.0.1', '::1'], true)) {
    http_response_code(403);
    exit('Solo se puede abrir desde la misma computadora (localhost).');
}
ini_set('display_errors', '0');
set_time_limit(300);
require_once __DIR__ . '/config/database.php';

// Columnas de cada tabla en PostgreSQL (en orden de dependencias) y cuáles son booleanas
$tables = [
    'users' => ['id,name,username,email,password_hash,status,role,must_change_password,created_at,updated_at', ['must_change_password']],
    'categories' => ['id,name,status', []],
    'payment_methods' => ['id,name,status', []],
    'inputs' => ['id,name,unit,package_type,package_quantity,package_content_unit,status,min_stock', []],
    'products' => ['id,name,description,category_id,type,price,is_available,status,image_path', ['is_available']],
    'preparations' => ['id,name,description,yield_quantity,yield_unit,yield_estimated,created_at,updated_at', ['yield_estimated']],
    'preparation_inputs' => ['id,preparation_id,input_id,quantity,is_estimated', ['is_estimated']],
    'recipes' => ['id,product_id,input_id,quantity', []],
    'product_components' => ['id,product_id,input_id,preparation_id,quantity,is_estimated,delivery_mode', ['is_estimated']],
    'orders' => ['id,user_id,order_status,payment_status,delivery_status,delivery_mode,customer_name,total,created_at,confirmed_at,delivered_at,cancelled_at', []],
    'order_items' => ['id,order_id,product_id,quantity,unit_price,subtotal,standard_unit_cost', []],
    'payments' => ['id,order_id,payment_method_id,amount,cash_received,change_amount,paid_at', []],
    'purchases' => ['id,purchase_date,supplier,buyer,ticket_path,payment_method_id,user_id,total,created_at,updated_at', []],
    'purchase_items' => ['id,purchase_id,input_id,quantity,unit_cost,subtotal,content_per_package,content_unit,total_base_quantity', []],
    'purchase_history' => ['id,purchase_id,changed_by,previous_data,new_data,change_reason,changed_at', []],
    'expenses' => ['id,amount,reason,user_id,status,created_at,updated_at,cancelled_by,cancelled_at,cancellation_reason', []],
    'expense_history' => ['id,expense_id,action,previous_data,new_data,change_reason,changed_by,changed_at', []],
    'waste_records' => ['id,affected_type,input_id,product_id,preparation_id,quantity,is_approximate,waste_date,reason,classification,estimated_unit_cost,estimated_total_cost,cost_status,user_id,created_at', ['is_approximate']],
    'inventory_movements' => ['id,input_id,movement_type,quantity,unit_cost,reference_type,reference_id,note,user_id,created_at', []],
    'order_test_invoices' => ['order_id,request_id,request_xml,stamped_xml,uuid', []],
    'work_location' => ['id,name,latitude,longitude,radius_m,updated_by,updated_at', []],
    'attendance' => ['id,user_id,type,latitude,longitude,accuracy_m,distance_m,note,created_at', []],
];

function mysqlColumns($table)
{
    global $pdo;
    $s = $pdo->prepare('SELECT LOWER(COLUMN_NAME) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?');
    $s->execute([$table]);
    return $s->fetchAll(PDO::FETCH_COLUMN);
}

function pgValue($v, $bool)
{
    if ($v === null) return 'null';
    if ($bool) return ((int)$v) ? 'true' : 'false';
    $v = (string)$v;
    if (preg_match('/^0000-00-00/', $v)) return 'null';
    return "'" . str_replace("'", "''", $v) . "'";
}

$counts = [];
foreach ($tables as $t => [$cols]) {
    $have = mysqlColumns($t);
    $counts[$t] = $have ? (int)$pdo->query("SELECT COUNT(*) FROM `$t`")->fetchColumn() : null;
}

$uploads = [];
foreach (['products', 'tickets'] as $folder) {
    foreach (glob(__DIR__ . "/uploads/$folder/*") ?: [] as $file) {
        if (is_file($file) && preg_match('/^[A-Za-z0-9_.-]+$/', basename($file))) $uploads[] = [$folder, $file];
    }
}

$download = $_GET['download'] ?? '';

if ($download === 'datos') {
    header('Content-Type: application/sql; charset=utf-8');
    header('Content-Disposition: attachment; filename="1_datos_la_obra_supabase.sql"');
    echo "-- Datos de La Obra (MySQL) para Supabase · generado " . date('Y-m-d H:i') . "\n";
    echo "-- Pegar en Supabase → SQL Editor → Run. REEMPLAZA los datos que haya en la_obra_v2.\n";
    echo "-- Antes debes haber corrido supabase/instalar_todo.sql.\n\n";
    echo "begin;\n";
    echo "set local session_replication_role = replica; -- permite cargar en cualquier orden\n";
    echo "truncate " . implode(', ', array_map(fn($t) => "la_obra_v2.$t", array_keys($tables))) . ", la_obra_v2.sessions restart identity cascade;\n\n";
    foreach ($tables as $t => [$cols, $bools]) {
        $have = mysqlColumns($t);
        if (!$have) { echo "-- $t: no existe en MySQL (se omite)\n"; continue; }
        $use = array_values(array_filter(explode(',', $cols), fn($c) => in_array($c, $have, true)));
        $key = $t === 'order_test_invoices' ? 'order_id' : 'id';
        $stmt = $pdo->query('SELECT ' . implode(',', array_map(fn($c) => "`$c`", $use)) . " FROM `$t` ORDER BY `$key`");
        $n = 0;
        while ($r = $stmt->fetch(PDO::FETCH_ASSOC)) {
            if ($n % 200 === 0) {
                if ($n) echo ";\n";
                echo "insert into la_obra_v2.$t (" . implode(',', $use) . ") values\n";
            } else {
                echo ",\n";
            }
            echo '(' . implode(',', array_map(fn($c) => pgValue($r[$c], in_array($c, $bools, true)), $use)) . ')';
            $n++;
        }
        if ($n) echo ";\n";
        echo "-- $t: $n registro(s)\n";
        if ($key === 'id' && $n) {
            echo "select setval(pg_get_serial_sequence('la_obra_v2.$t', 'id'), (select max(id) from la_obra_v2.$t));\n";
        }
        echo "\n";
    }
    echo "commit;\n";
    echo "select 'Datos de La Obra cargados' as resultado;\n";
    exit;
}

if ($download === 'fotos') {
    header('Content-Type: application/sql; charset=utf-8');
    header('Content-Disposition: attachment; filename="2_fotos_la_obra_supabase.sql"');
    echo "-- Fotos de productos y tickets de La Obra para Supabase · " . count($uploads) . " archivo(s)\n";
    echo "-- Cada línea es una foto. Si el editor no acepta el archivo completo, córrelo por partes.\n\n";
    $finfo = new finfo(FILEINFO_MIME_TYPE);
    foreach ($uploads as [$folder, $file]) {
        $mime = $finfo->file($file);
        if (!in_array($mime, ['image/jpeg', 'image/png', 'image/webp'], true)) continue;
        $path = "uploads/$folder/" . basename($file);
        echo "insert into la_obra_v2.files(path,mime,data) values ('$path','$mime',decode('" . base64_encode(file_get_contents($file)) . "','base64')) on conflict (path) do update set mime=excluded.mime, data=excluded.data;\n";
    }
    echo "select 'Fotos cargadas' as resultado;\n";
    exit;
}
?>
<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>Pasar La Obra a Supabase</title>
<style>
body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#f5f5f2;color:#17181a;margin:0;padding:32px 16px}
main{max-width:720px;margin:0 auto;background:#fff;border:1px solid #e6e4de;border-radius:16px;padding:24px}
h1{margin:0 0 6px;font-size:22px} table{width:100%;border-collapse:collapse;margin:16px 0;font-size:14px}
td{padding:6px 4px;border-bottom:1px solid #f0efeb} td:last-child{text-align:right;font-variant-numeric:tabular-nums}
a.btn{display:inline-block;margin:6px 8px 0 0;padding:10px 16px;border-radius:10px;background:#17181a;color:#fff;text-decoration:none;font-weight:600}
a.btn.light{background:#ffc526;color:#4a3600} .n{color:#9a9da3} .warn{background:#fdf1dc;color:#7a4900;padding:10px 12px;border-radius:10px;font-size:14px}
</style></head><body><main>
<h1>Pasar La Obra a Supabase</h1>
<div class="n">Base MySQL: <strong><?= htmlspecialchars($pdo->query('SELECT DATABASE()')->fetchColumn()) ?></strong> · solo lectura</div>
<table>
<?php foreach ($counts as $t => $n): ?>
  <tr><td><?= htmlspecialchars($t) ?></td><td><?= $n === null ? '<span class="n">no existe</span>' : $n ?></td></tr>
<?php endforeach; ?>
  <tr><td><strong>Fotos (uploads/)</strong></td><td><strong><?= count($uploads) ?></strong></td></tr>
</table>
<a class="btn" href="?download=datos">1 · Datos</a>
<?php if ($uploads): ?><a class="btn light" href="?download=fotos">2 · Fotos</a><?php endif; ?>
<p class="warn">El archivo de datos <strong>reemplaza</strong> lo que haya en Supabase. Úsalo una vez, al migrar. Los usuarios conservan su contraseña.</p>
</main></body></html>
