<?php
declare(strict_types=1);

/**
 * Safe demo-data seeder for Digi Bile Pay.
 * Default mode is DRY RUN. Pass --apply to insert.
 * Inserts only clearly tagged sample master/workflow records for company 1.
 * Does not modify existing rows, users, accounts, fiscal years or financial ledgers.
 */
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

$companyId = 1;
$userId = 1;
$apply = in_array('--apply', $argv, true);

try {
    $pdo = new PDO("mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4", $user, $pass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $guard = $pdo->prepare("SELECT COUNT(*) FROM companies WHERE id=? AND status='active'");
    $guard->execute([$companyId]);
    if ((int)$guard->fetchColumn() !== 1) throw new RuntimeException('Company 1 is not active; refusing to seed.');
    $guard = $pdo->prepare("SELECT COUNT(*) FROM users WHERE id=? AND company_id=? AND role_id=1 AND status='active'");
    $guard->execute([$userId, $companyId]);
    if ((int)$guard->fetchColumn() !== 1) throw new RuntimeException('Expected active super-admin user 1 in company 1; refusing to seed.');

    $pdo->beginTransaction();
    $added = ['customers'=>0,'merchants'=>0,'products'=>0,'loan_plans'=>0,'leads'=>0,'dimensions'=>0,'site_faq'=>0];
    $now = date('Y-m-d H:i:s');

    $customerNames = ['آرمان رضایی','نگار محمدی','پارسا کریمی','هستی احمدی','سامان مرادی','ترانه حسینی','امیرحسین جعفری','رها صادقی','کیان نوری','آوا کاظمی'];
    $customerIds = [];
    for ($i=1; $i<=10; $i++) {
        $nc = sprintf('000000%04d', $i);
        $mobile = sprintf('0000000%04d', $i);
        $s = $pdo->prepare("SELECT id FROM customers WHERE company_id=? AND national_code=?");
        $s->execute([$companyId,$nc]);
        $id = $s->fetchColumn();
        if (!$id) {
            $s = $pdo->prepare("INSERT INTO customers (company_id,national_code,full_name,mobile,credit_limit,wallet_balance,status) VALUES (?,?,?,?,?,?, 'active')");
            $s->execute([$companyId,$nc,'[نمونه آزمایشی] '.$customerNames[$i-1],$mobile,50000000,0]);
            $id = (int)$pdo->lastInsertId(); $added['customers']++;
        }
        $customerIds[] = (int)$id;
    }

    $merchantIds = [];
    for ($i=1; $i<=10; $i++) {
        $name = sprintf('[نمونه آزمایشی] فروشگاه %02d', $i);
        $s=$pdo->prepare("SELECT id FROM merchants WHERE company_id=? AND name=?");
        $s->execute([$companyId,$name]); $id=$s->fetchColumn();
        if (!$id) {
            $s=$pdo->prepare("INSERT INTO merchants (company_id,name,contact_name,mobile,commission_percent,status) VALUES (?,?,?,?,?,'active')");
            $s->execute([$companyId,$name,'کاربر نمونه',sprintf('000000%05d',$i),2.50]);
            $id=(int)$pdo->lastInsertId(); $added['merchants']++;
        }
        $merchantIds[]=(int)$id;
    }

    $productNames=['گوشی هوشمند نمونه','لپ‌تاپ نمونه','تبلت نمونه','هدفون بی‌سیم نمونه','ساعت هوشمند نمونه','مانیتور نمونه','پرینتر نمونه','دوربین نمونه','اسپیکر نمونه','مودم نمونه'];
    $productIds=[];
    for($i=1;$i<=10;$i++){
        $sku=sprintf('DEMO-SKU-%03d',$i);
        $s=$pdo->prepare("SELECT id FROM products WHERE company_id=? AND sku=?");
        $s->execute([$companyId,$sku]); $id=$s->fetchColumn();
        if(!$id){
            $s=$pdo->prepare("INSERT INTO products (company_id,merchant_id,name,sku,price,stock,status) VALUES (?,?,?,?,?,?,'active')");
            $s->execute([$companyId,$merchantIds[$i-1],'[نمونه آزمایشی] '.$productNames[$i-1],$sku,($i*1000000),20]);
            $id=(int)$pdo->lastInsertId(); $added['products']++;
        }
        $productIds[]=(int)$id;
    }

    for($i=1;$i<=10;$i++){
        $name=sprintf('[نمونه آزمایشی] طرح %02d ماهه',$i*3);
        $s=$pdo->prepare("SELECT id FROM loan_plans WHERE company_id=? AND name=?");
        $s->execute([$companyId,$name]);
        if(!$s->fetchColumn()){
            $s=$pdo->prepare("INSERT INTO loan_plans (company_id,name,months,annual_rate_percent,fee_percent,min_amount,max_amount,is_active,late_fee_daily_percent) VALUES (?,?,?,?,?,?,?,?,?)");
            $s->execute([$companyId,$name,$i*3,18.00,1.00,1000000,50000000,1,0.05]); $added['loan_plans']++;
        }
    }

    for($i=1;$i<=10;$i++){
        $name='[نمونه آزمایشی] مرکز هزینه '.sprintf('%02d',$i);
        $code=sprintf('D%03d',$i);
        $s=$pdo->prepare("SELECT id FROM dimensions WHERE company_id=? AND kind='cost_center' AND code=?");
        $s->execute([$companyId,$code]);
        if(!$s->fetchColumn()){
            $s=$pdo->prepare("INSERT INTO dimensions (company_id,kind,code,name,is_active,created_at) VALUES (?,'cost_center',?,?,1,?)");
            $s->execute([$companyId,$code,$name,$now]); $added['dimensions']++;
        }
    }

    for($i=1;$i<=10;$i++){
        $mobile=sprintf('000000%05d',$i);
        $s=$pdo->prepare("SELECT id FROM leads WHERE company_id=? AND mobile=? AND message LIKE '[نمونه آزمایشی]%'");
        $s->execute([$companyId,$mobile]);
        if(!$s->fetchColumn()){
            $s=$pdo->prepare("INSERT INTO leads (company_id,full_name,mobile,national_code,requested_amount,plan_id,message,status,ip,created_at) VALUES (?,?,?,?,?,?,?,'new','192.0.2.77',?)");
            $s->execute([$companyId,'[نمونه آزمایشی] متقاضی '.sprintf('%02d',$i),$mobile,null,($i*2000000),null,'[نمونه آزمایشی] درخواست تست شماره '.$i,$now]); $added['leads']++;
        }
    }

    $faqs=[
        ['شرایط ثبت‌نام چیست؟','برای ثبت‌نام، اطلاعات هویتی و شماره همراه معتبر لازم است.'],
        ['چگونه درخواست تسهیلات بدهم؟','پس از ثبت‌نام، طرح مناسب را انتخاب و درخواست خود را ثبت کنید.'],
        ['وضعیت درخواست را از کجا ببینم؟','وضعیت درخواست از پنل کاربری قابل پیگیری است.'],
        ['اقساط چگونه پرداخت می‌شوند؟','پرداخت اقساط طبق روش‌های فعال‌شده در سامانه انجام می‌شود.'],
        ['آیا امکان تسویه زودتر وجود دارد؟','شرایط تسویه زودتر به مقررات طرح انتخابی بستگی دارد.'],
        ['چگونه با پشتیبانی تماس بگیرم؟','از راه‌های ارتباطی درج‌شده در صفحه تماس استفاده کنید.'],
        ['اعتبارسنجی چقدر زمان می‌برد؟','زمان بررسی به کامل بودن مدارک و فرایند اعتبارسنجی بستگی دارد.'],
        ['آیا امکان تغییر شماره همراه هست؟','برای تغییر شماره همراه، درخواست خود را به پشتیبانی اعلام کنید.'],
        ['رسید پرداخت را کجا ببینم؟','رسید پرداخت در سوابق مالی پنل نمایش داده می‌شود.'],
        ['در صورت خطای پرداخت چه کنم؟','ابتدا وضعیت تراکنش را بررسی و سپس با پشتیبانی تماس بگیرید.']
    ];
    foreach($faqs as $i=>$faq){
        $question='[نمونه آزمایشی] '.$faq[0];
        $s=$pdo->prepare("SELECT id FROM site_faq WHERE company_id=? AND question=?");
        $s->execute([$companyId,$question]);
        if(!$s->fetchColumn()){
            $s=$pdo->prepare("INSERT INTO site_faq (company_id,question,answer,sort_order) VALUES (?,?,?,?)");
            $s->execute([$companyId,$question,$faq[1],900+$i]); $added['site_faq']++;
        }
    }

    if($apply){ $pdo->commit(); }
    else { $pdo->rollBack(); }
    echo $apply ? "DEMO SEED COMPLETED (company_id=1)\\n" : "DRY RUN OK; no rows were saved. Run with --apply to insert.\\n";
    foreach($added as $table=>$count) echo $table.": ".$count.($apply ? " inserted" : " would insert")."\\n";
    echo "Existing users, company 2, accounts, fiscal years and financial ledgers were not modified.\\n";
} catch(Throwable $e) {
    if(isset($pdo) && $pdo->inTransaction()) $pdo->rollBack();
    $m=$e->getMessage();
    foreach([$pass??'',$user??'',$db??''] as $secret) if($secret!=='') $m=str_replace($secret,'[redacted]',$m);
    fwrite(STDERR,"ERROR: ".get_class($e).": ".$m."\\n");
    exit(1);
}
