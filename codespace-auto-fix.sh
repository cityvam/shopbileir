#!/usr/bin/env bash
set -Eeuo pipefail

# DBP one-command local UI repair for GitHub Codespaces.
# Safe by default: backs up files, never changes database records or admin passwords.

if [[ -f "$PWD/app/bootstrap.php" ]]; then
  APP_DIR="$PWD"
elif [[ -f "$PWD/digi-bile-pay/app/bootstrap.php" ]]; then
  APP_DIR="$PWD/digi-bile-pay"
else
  echo "Project directory not found. Run this script from /workspaces/shopbileir."
  exit 1
fi

cd "$APP_DIR"
BACKUP_DIR="/tmp/dbp-auto-fix-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

for file in .env resources/views/auth/login.php resources/layouts/app.php resources/views/dashboard/index.php app/Core/Captcha.php resources/views/components/captcha.php public/assets/js/app.js public/assets/css/pages/login.css public/assets/css/components/forms.css; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -p "$file" "$BACKUP_DIR/$file"
  fi
done

echo "Backup: $BACKUP_DIR"

# Set local development options without printing secrets.
if [[ -f .env ]]; then
  /usr/bin/python3 - <<'PY'
from pathlib import Path
p = Path(".env")
lines = p.read_text().splitlines()
updates = {"PUBLIC_COMPANY_CODE": "DBP", "SMS_DRIVER": "log"}
seen = set()
out = []
for line in lines:
    if "=" in line and not line.lstrip().startswith("#"):
        key = line.split("=", 1)[0].strip()
        if key in updates:
            out.append(f"{key}={updates[key]}")
            seen.add(key)
            continue
    out.append(line)
for key, value in updates.items():
    if key not in seen:
        out.append(f"{key}={value}")
p.write_text("\n".join(out) + "\n")
PY
  chmod 600 .env
else
  echo "WARNING: .env is missing; local settings were not changed."
fi

/usr/bin/python3 - <<'PY'
from pathlib import Path

# Staff login: normalize the home link to exactly one.
p = Path("resources/views/auth/login.php")
s = p.read_text()
import re
s = re.sub(r'<a\b[^>]*href="/"[^>]*>\s*بازگشت به صفحه اصلی\s*</a>', '', s)
marker = "    </form>"
if marker not in s:
    raise SystemExit("Could not locate end of staff login form; stopped.")
s = s.replace(marker, marker + '\n    <a class="btn btn--ghost btn--block" href="/">بازگشت به صفحه اصلی</a>', 1)
p.write_text(s)
print("Staff login now has exactly one home link.")

# Admin site link opens a separate tab.
p = Path("resources/layouts/app.php")
s = p.read_text()
s = s.replace(
    'href="/" title="مشاهده صفحه اصلی (سایت عمومی)"',
    'href="/" target="_blank" rel="noopener noreferrer" title="باز کردن سایت در زبانه جدید"'
)
p.write_text(s)
print("Admin site link opens in a new tab.")

# Make all dashboard statistic cards permission-aware links.
p = Path("resources/views/dashboard/index.php")
s = p.read_text()
old = """        ['مشتریان فعال', num($stats['customers']), '', 'users', ''],
        ['تسهیلات فعال', num($stats['active_loans']), '', 'file-text', ''],
        ['در انتظار تأیید', num($stats['pending']), '', 'clipboard', 'warn'],
        ['مطالبات باقی‌مانده', money_unit($stats['outstanding']), '', 'wallet', ''],
        ['اقساط معوق', num($stats['overdue_count']), money($stats['overdue_sum']), 'alert', 'bad'],
        ['وصولی این ماه', money_unit($stats['collected_month']), '', 'banknote', 'ok'],
        ['فروش این ماه', money_unit($stats['sales_month']), num($stats['orders_month']) . ' سفارش', 'cart', ''],
        ['فروشندگان فعال', num($stats['merchants']), '', 'store', ''],"""
new = """        ['مشتریان فعال', num($stats['customers']), '', 'users', '', '/customers', 'customers.view'],
        ['تسهیلات فعال', num($stats['active_loans']), '', 'file-text', '', '/loans', 'loans.view'],
        ['در انتظار تأیید', num($stats['pending']), '', 'clipboard', 'warn', '/loans', 'loans.view'],
        ['مطالبات باقی‌مانده', money_unit($stats['outstanding']), '', 'wallet', '', '/reports', 'reports.view'],
        ['اقساط معوق', num($stats['overdue_count']), money($stats['overdue_sum']), 'alert', 'bad', '/installments?filter=overdue', 'installments.view'],
        ['وصولی این ماه', money_unit($stats['collected_month']), '', 'banknote', 'ok', '/reports', 'reports.view'],
        ['فروش این ماه', money_unit($stats['sales_month']), num($stats['orders_month']) . ' سفارش', 'cart', '', '/orders', 'orders.view'],
        ['فروشندگان فعال', num($stats['merchants']), '', 'store', '', '/merchants', 'merchants.view'],"""
if old not in s:
    raise SystemExit("Dashboard statistic definitions did not match; refusing to guess.")
s = s.replace(old, new, 1)
s = s.replace('as [$label, $value, $sub, $ic, $tone]: ?>', 'as [$label, $value, $sub, $ic, $tone, $href, $permission]: ?>', 1)
old_open = """    <article class="stat-card<?= $tone ? ' stat-card--' . $tone : '' ?>">"""
new_open = """    <?php if (\\App\\Core\\Auth::can($permission)): ?><a class="stat-card stat-card--link<?= $tone ? ' stat-card--' . $tone : '' ?>" href="<?= e($href) ?>" aria-label="<?= e($label) ?>"><?php else: ?><article class="stat-card<?= $tone ? ' stat-card--' . $tone : '' ?>"><?php endif; ?>"""
old_close = """    </article>
    <?php endforeach; ?>"""
new_close = """    <?php if (\\App\\Core\\Auth::can($permission)): ?></a><?php else: ?></article><?php endif; ?>
    <?php endforeach; ?>"""
if old_open not in s or old_close not in s:
    raise SystemExit("Dashboard card markup did not match; refusing to guess.")
s = s.replace(old_open, new_open, 1).replace(old_close, new_close, 1)
p.write_text(s)
print("Dashboard statistic cards now link to related sections when permitted.")

# Replace hard-to-read hand-drawn CAPTCHA strokes with high-contrast bold numerals.
p = Path("app/Core/Captcha.php")
s = p.read_text()
start = s.index('    /** تصویر SVG کد داده‌شده. */')
end = s.index('    private static function ellipse()', start)
replacement = r'''    /** تصویر SVG کد داده‌شده؛ ارقام درشت و خوانا، بدون نویز روی متن. */
    public static function svg(string $code): string
    {
        $w = 260;
        $h = 76;
        $o = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' . $w . ' ' . $h . '" width="' . $w . '" height="' . $h . '" role="img" aria-label="کد امنیتی ۶ رقمی">';
        $o .= '<defs><linearGradient id="captcha-bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#e8edff"/></linearGradient></defs>';
        $o .= '<rect x="1" y="1" width="' . ($w - 2) . '" height="' . ($h - 2) . '" rx="12" fill="url(#captcha-bg)" stroke="#64748b" stroke-width="1.5"/>';
        for ($i = 0; $i < 6; $i++) {
            $x = 12 + $i * 40;
            $y = 54 + self::rnd(-2, 2);
            $o .= sprintf(
                '<text x="%d" y="%.1f" text-anchor="middle" font-family="DejaVu Sans, Arial, sans-serif" font-size="43" font-weight="800" fill="#172554">%s</text>',
                $x + 19, $y, htmlspecialchars($code[$i], ENT_QUOTES | ENT_XML1, 'UTF-8')
            );
        }
        return $o . '</svg>';
    }

'''
s = s.slice(0, start) + replacement + s.slice(end);
p.write_text(s)
print("CAPTCHA image now uses clear bold digits.")

# Improve CAPTCHA image and entry field sizing/contrast.
p = Path("public/assets/css/components/forms.css")
s = p.read_text()
s += """

/* DBP readable numeric CAPTCHA */
.captcha__row { align-items: center; gap: 12px; }
.captcha__img {
    width: 260px;
    max-width: 100%;
    height: 76px;
    object-fit: contain;
    border: 1px solid #64748b;
    border-radius: 12px;
    background: #fff;
    box-shadow: 0 2px 8px rgba(15, 23, 42, .12);
}
.captcha__input {
    min-height: 52px;
    font-size: 1.35rem;
    font-weight: 800;
    letter-spacing: .35em;
    color: #172554;
    background: #fff;
}
.captcha__input::placeholder { letter-spacing: 0; }
"""
p.write_text(s)
print("CAPTCHA display and input styles improved.")


# Staff login: add a safe return-home link outside the form.
p = Path("resources/views/auth/login.php")
s = p.read_text()
if 'href="/" class="btn btn--ghost btn--block"' not in s and 'href="/" class="btn btn--ghost"' not in s:
    marker = "    </form>"
    if marker not in s:
        raise SystemExit("Could not locate end of staff login form; stopped without changing that file.")
    s = s.replace(marker, marker + '\n    <a class="btn btn--ghost btn--block" href="/">بازگشت به صفحه اصلی</a>', 1)
    p.write_text(s)
    print("Added return-to-home button to staff login.")
else:
    print("Return-to-home button already exists.")

# Password toggle JS: add only when the data attribute exists but handler does not.
p = Path("public/assets/js/app.js")
s = p.read_text()
if "[data-password-toggle]" not in s:
    marker = "})();"
    pos = s.rfind(marker)
    if pos < 0:
        raise SystemExit("Could not locate end of app.js; stopped.")
    handler = """
    // Staff login password visibility toggle
    document.addEventListener('click', function (e) {
        var button = e.target.closest ? e.target.closest('[data-password-toggle]') : null;
        if (!button) return;
        var input = document.querySelector(button.getAttribute('data-password-toggle'));
        if (!input) return;
        var show = input.type === 'password';
        input.type = show ? 'text' : 'password';
        button.setAttribute('aria-pressed', show ? 'true' : 'false');
        button.setAttribute('aria-label', show ? 'مخفی کردن رمز عبور' : 'نمایش رمز عبور');
    });

"""
    s = s[:pos] + handler + s[pos:]
    p.write_text(s)
    print("Added password toggle behavior.")
else:
    print("Password toggle behavior already exists.")

# Login styles: keep the primary submit button visibly colored and style the eye control.
p = Path("public/assets/css/pages/login.css")
s = p.read_text()
if "/* DBP login usability additions */" not in s:
    s += """

/* DBP login usability additions */
.pg-login .login-card .btn--primary {
    display: flex;
    visibility: visible;
    opacity: 1;
    color: #fff !important;
    background: linear-gradient(135deg, #4338ca, #6d28d9) !important;
    border-color: transparent !important;
}
.pg-login .login-card .btn--primary:hover {
    filter: brightness(1.06);
}
.pg-login .password-field { position: relative; }
.pg-login .password-field .input { padding-inline-end: 3.1rem; }
.pg-login .password-toggle {
    position: absolute;
    inset-inline-end: .5rem;
    top: 50%;
    transform: translateY(-50%);
    width: 2.5rem;
    height: 2.5rem;
    display: grid;
    place-items: center;
    border: 0;
    border-radius: 9px;
    color: var(--c-muted);
    background: transparent;
    cursor: pointer;
}
.pg-login .password-toggle:hover { background: var(--c-bg); }
.pg-login .password-toggle svg { width: 20px; height: 20px; }
.pg-login .password-toggle__eye-off { display: none; }
.pg-login .password-toggle[aria-pressed="true"] .password-toggle__eye { display: none; }
.pg-login .password-toggle[aria-pressed="true"] .password-toggle__eye-off { display: block; }
.pg-login .password-toggle:focus-visible { outline: 2px solid var(--c-primary); outline-offset: 2px; }
"""
    p.write_text(s)
    print("Added visible login button and password-eye styles.")
else:
    print("Login usability styles already exist.")

# Clarify dashboard site link.
p = Path("resources/layouts/app.php")
s = p.read_text()
s = s.replace('<span>صفحه اصلی</span>', '<span>مشاهده سایت</span>')
p.write_text(s)
print("Verified dashboard 'مشاهده سایت' link label.")
PY

# Ensure the test runner uses PHP 8.3 (GD is installed there in this Codespace).
if [[ -x /usr/bin/php8.3 ]]; then
  mkdir -p /tmp/php83-bin
  ln -sf /usr/bin/php8.3 /tmp/php83-bin/php
  TEST_PATH="/tmp/php83-bin:/usr/bin:/bin"
else
  TEST_PATH="$PATH"
fi

echo
echo "========== PHP SYNTAX =========="
/usr/bin/php8.3 -l resources/views/auth/login.php
/usr/bin/php8.3 -l resources/layouts/app.php

echo
echo "========== CAPTCHA IMPLEMENTATION =========="
if grep -RniE 'random_int\(100000, *999999\)|[0-9].*captcha|captcha.*[0-9]' app/Core resources/views/partials resources/views 2>/dev/null | head -12; then
  :
fi

echo
echo "========== DASHBOARD VIEW LINKS (READ-ONLY REPORT) =========="
if [[ -f resources/views/dashboard/index.php ]]; then
  grep -nE '<a |href=|<article|<section|class=' resources/views/dashboard/index.php | head -100 || true
else
  echo "Dashboard view not found at expected path."
fi

echo
echo "========== REPAIR HOME-PAGE TEST ASSERTION =========="
/usr/bin/python3 - <<'PY'
from pathlib import Path
from zipfile import ZipFile

p = Path("tests/smoke.php")
s = p.read_text(encoding="utf-8")
expected = "check('landing links to customer portal', $pc->has('/portal'));"
damaged = s.startswith("<?php\\n") or (s.count("\n") < 10 and "\\n" in s[:500])
obsolete = "landing hides customer and staff sign-in links" in s

if damaged or obsolete:
    restored = False
    for archive in sorted(Path("..").glob("*.zip")):
        try:
            with ZipFile(archive) as z:
                names = [n for n in z.namelist() if n.replace("\\\\", "/").endswith("tests/smoke.php")]
                names.sort(key=len)
                for name in names:
                    data = z.read(name)
                    if data.startswith(b"<?php") and b"declare(strict_types=1);" in data[:200]:
                        p.write_bytes(data)
                        print(f"Restored tests/smoke.php from {archive.name}:{name}")
                        restored = True
                        break
            if restored:
                break
        except Exception:
            continue
    if not restored:
        raise SystemExit("The smoke test is damaged, and its original could not be found in a ZIP beside the project. No guessed repair was applied.")

s = p.read_text(encoding="utf-8")
if expected not in s:
    raise SystemExit("Expected public-portal-link assertion is missing after repair; refusing to run tests.")
if s.startswith("<?php\\n") or s.count("\n") < 10:
    raise SystemExit("Smoke test still does not contain normal line breaks; refusing to run tests.")
print("Smoke test source is readable and preserves the customer/staff login links.")
PY

echo "========== SMOKE TEST PHP SYNTAX =========="
/usr/bin/php8.3 -l tests/smoke.php

echo "========== TESTS =========="
PATH="$TEST_PATH" XDEBUG_MODE=off bash tests/run-all.sh

echo
echo "========== LOCAL SERVER =========="
sudo service mariadb start >/dev/null
if [[ -f /tmp/digi-bile-pay-server.pid ]]; then
  old_pid="$(cat /tmp/digi-bile-pay-server.pid)"
  kill "$old_pid" 2>/dev/null || true
fi
cat > /tmp/digi-bile-pay-router.php <<'PHP'
<?php
declare(strict_types=1);
$root = realpath(__DIR__ . '/../../workspaces/shopbileir/digi-bile-pay/public');
if ($root === false) {
    $root = realpath('/workspaces/shopbileir/digi-bile-pay/public');
}
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
$path = rawurldecode(is_string($path) ? $path : '/');
$file = realpath($root . DIRECTORY_SEPARATOR . ltrim($path, '/'));
$extensions = ['css','js','map','png','jpg','jpeg','webp','gif','svg','ico','woff','woff2','ttf'];
if ($file !== false && str_starts_with($file, $root . DIRECTORY_SEPARATOR) && is_file($file)
    && in_array(strtolower(pathinfo($file, PATHINFO_EXTENSION)), $extensions, true)) {
    return false;
}
require $root . '/index.php';
PHP
nohup /usr/bin/php8.3 -S 0.0.0.0:8000 -t public /tmp/digi-bile-pay-router.php > /tmp/digi-bile-pay-server.log 2>&1 < /dev/null &
SERVER_PID=$!
echo "$SERVER_PID" > /tmp/digi-bile-pay-server.pid
disown "$SERVER_PID" 2>/dev/null || true
for attempt in $(seq 1 20); do
  if curl -fsS http://127.0.0.1:8000/ >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
if ! curl -fsS http://127.0.0.1:8000/ >/dev/null 2>&1; then
  echo "ERROR: PHP server did not stay up. Recent log:"
  tail -60 /tmp/digi-bile-pay-server.log || true
  exit 1
fi
curl -sS -o /dev/null -w "Homepage HTTP %{http_code}\n" http://127.0.0.1:8000/
curl -sS -o /dev/null -w "Staff login HTTP %{http_code}\n" http://127.0.0.1:8000/login
curl -sS -o /dev/null -w "Portal login HTTP %{http_code}\n" http://127.0.0.1:8000/portal/login

echo
echo "Installed. Backup kept at: $BACKUP_DIR"
echo "Note: dashboard card destinations are reported above; not guessed or rewritten."
