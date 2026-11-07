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

for file in .env resources/views/auth/login.php resources/layouts/app.php public/assets/js/app.js public/assets/css/pages/login.css; do
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
echo $! > /tmp/digi-bile-pay-server.pid
sleep 2
curl -sS -o /dev/null -w "Homepage HTTP %{http_code}\n" http://127.0.0.1:8000/
curl -sS -o /dev/null -w "Staff login HTTP %{http_code}\n" http://127.0.0.1:8000/login
curl -sS -o /dev/null -w "Portal login HTTP %{http_code}\n" http://127.0.0.1:8000/portal/login

echo
echo "Installed. Backup kept at: $BACKUP_DIR"
echo "Note: dashboard card destinations are reported above; not guessed or rewritten."
