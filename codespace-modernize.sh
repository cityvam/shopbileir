#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -f "$PWD/app/bootstrap.php" ]]; then APP_DIR="$PWD"
elif [[ -f "$PWD/digi-bile-pay/app/bootstrap.php" ]]; then APP_DIR="$PWD/digi-bile-pay"
else echo "Run from /workspaces/shopbileir"; exit 1; fi
cd "$APP_DIR"

BACKUP="/tmp/dbp-modern-ui-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
for f in resources/layouts/app.php resources/views/auth/login.php resources/views/portal/login.php public/assets/css/pages/login.css; do
  if [[ -f "$f" ]]; then mkdir -p "$BACKUP/$(dirname "$f")"; cp -p "$f" "$BACKUP/$f"; fi
done
echo "Backup: $BACKUP"

/usr/bin/python3 - <<'PY'
from pathlib import Path
import re

layout = Path("resources/layouts/app.php")
s = layout.read_text()
# Add one dashboard return action to the shared authenticated layout.
if "topbar__dashboard" not in s:
    pattern = r'(<a\\b[^>]*class="[^"]*topbar__home[^"]*"[^>]*>.*?</a>)'
    m = re.search(pattern, s, flags=re.S)
    if not m:
        # Fall back to the known public-site link if class order differs.
        m = re.search(r'(<a\\b[^>]*href="/"[^>]*>.*?مشاهده سایت.*?</a>)', s, flags=re.S)
    if not m:
        raise SystemExit("Could not safely locate the shared topbar site link.")
    dashboard = '''\n<a class="btn btn--secondary btn--sm topbar__dashboard" href="/dashboard" title="بازگشت به داشبورد"><span aria-hidden="true">⌂</span><span>بازگشت به داشبورد</span></a>'''
    s = s[:m.end()] + dashboard + s[m.end():]
layout.write_text(s)
print("Added dashboard return link to shared authenticated layout.")

# Ensure the modern stylesheet is loaded once in the shared layout.
s = layout.read_text()
link = '<link rel="stylesheet" href="/assets/css/modern-ui.css">'
if link not in s:
    if "</head>" not in s:
        raise SystemExit("Shared layout has no closing head tag; stylesheet was not linked.")
    s = s.replace("</head>", "    " + link + "\\n</head>", 1)
    layout.write_text(s)
print("Loaded modern UI stylesheet in the shared layout.")

# Login pages use the existing login stylesheet; append modern login treatment there.
css = Path("public/assets/css/pages/login.css")
if css.exists():
    current = css.read_text()
    marker = "/* DBP modern login treatment */"
    if marker not in current:
        current += """

/* DBP modern login treatment */
.pg-login {
  min-height: 100vh;
  background:
    radial-gradient(ellipse at 12% 8%, rgba(99,102,241,.18), transparent 34rem),
    radial-gradient(ellipse at 88% 92%, rgba(14,165,233,.14), transparent 32rem),
    linear-gradient(145deg, #f8faff 0%, #eef2ff 48%, #f8fafc 100%);
}
.pg-login .login-card {
  border: 1px solid rgba(148,163,184,.22);
  border-radius: 26px;
  background: rgba(255,255,255,.92);
  box-shadow: 0 24px 70px rgba(30,41,59,.13), 0 3px 12px rgba(30,41,59,.05);
  backdrop-filter: blur(18px);
}
.pg-login .login-card h1 { color: #172554; letter-spacing: -.025em; }
.pg-login .login-card .input,
.pg-login .login-card select,
.pg-login .login-card textarea {
  min-height: 50px;
  border-radius: 13px;
  border-color: #dbe3f0;
  background: #fbfdff;
  transition: border-color .18s ease, box-shadow .18s ease, background .18s ease;
}
.pg-login .login-card .input:focus,
.pg-login .login-card select:focus,
.pg-login .login-card textarea:focus {
  border-color: #6366f1;
  background: #fff;
  box-shadow: 0 0 0 4px rgba(99,102,241,.12);
  outline: none;
}
.pg-login .login-card .btn { min-height: 48px; border-radius: 13px; font-weight: 750; }
.pg-login .login-card .btn--primary {
  background: linear-gradient(110deg, #4338ca, #6d28d9) !important;
  box-shadow: 0 9px 22px rgba(79,70,229,.22);
}
.pg-login .login-card .btn--primary:hover { transform: translateY(-1px); filter: brightness(1.04); }
.pg-login .captcha__img { border-radius: 12px; }
@media (max-width: 640px) {
  .pg-login { padding: 18px 12px; }
  .pg-login .login-card { border-radius: 20px; padding: 22px 18px; }
}
"""
        css.write_text(current)
        print("Modernized login page styling.")
    else:
        print("Login styling already modernized.")
else:
    print("WARNING: login.css not found; skipped login-specific styling.")
PY

cat > public/assets/css/modern-ui.css <<'CSS'
/* Digi Bile Pay — modern shared UI layer */
:root {
  --dbp-ink: #172554;
  --dbp-muted: #64748b;
  --dbp-line: #e2e8f0;
  --dbp-surface: #ffffff;
  --dbp-bg: #f5f7fc;
  --dbp-primary: #4f46e5;
  --dbp-primary-dark: #3730a3;
  --dbp-radius: 18px;
  --dbp-shadow: 0 10px 30px rgba(15,23,42,.055);
}
html { scroll-behavior: smooth; }
body { background: var(--dbp-bg); color: #1e293b; }
main, .main, .content, .page-content { min-width: 0; }
.topbar {
  background: rgba(255,255,255,.92);
  border-bottom: 1px solid rgba(226,232,240,.9);
  box-shadow: 0 4px 20px rgba(15,23,42,.035);
  backdrop-filter: blur(16px);
}
.topbar__dashboard {
  gap: 8px;
  border: 1px solid #c7d2fe !important;
  color: #3730a3 !important;
  background: #eef2ff !important;
  border-radius: 11px !important;
  font-weight: 750;
}
.topbar__dashboard:hover { background: #e0e7ff !important; transform: translateY(-1px); }
.stat-grid { gap: 16px; }
.stat-card, .card, .panel, .table-wrap, .filter-card {
  border: 1px solid rgba(226,232,240,.95);
  border-radius: var(--dbp-radius);
  background: var(--dbp-surface);
  box-shadow: var(--dbp-shadow);
}
.stat-card {
  position: relative;
  overflow: hidden;
  padding: 20px;
  transition: transform .2s ease, box-shadow .2s ease, border-color .2s ease;
}
.stat-card::before {
  content: "";
  position: absolute;
  inset: 0 0 auto;
  height: 3px;
  background: linear-gradient(90deg,#6366f1,#06b6d4);
  opacity: .7;
}
a.stat-card { color: inherit; text-decoration: none; }
a.stat-card:hover {
  transform: translateY(-4px);
  border-color: #c7d2fe;
  box-shadow: 0 16px 36px rgba(49,46,129,.11);
}
.stat-card__icon {
  display: inline-grid;
  place-items: center;
  width: 44px;
  height: 44px;
  border-radius: 14px;
  color: #4338ca;
  background: #eef2ff;
}
.stat-card__label { color: #64748b; font-weight: 650; }
.stat-card__value { color: var(--dbp-ink); font-size: clamp(1.2rem,2vw,1.65rem); }
.card, .panel { padding: clamp(16px,2vw,24px); }
.card__head, .panel__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
  margin-bottom: 16px;
}
.card__head h2, .panel__head h2 { color: var(--dbp-ink); font-weight: 800; }
.btn {
  min-height: 40px;
  border-radius: 11px;
  font-weight: 700;
  transition: transform .16s ease, box-shadow .16s ease, filter .16s ease;
}
.btn:hover { transform: translateY(-1px); }
.btn--primary {
  background: linear-gradient(110deg,#4f46e5,#6d28d9);
  box-shadow: 0 6px 16px rgba(79,70,229,.18);
}
.input, select, textarea {
  border-radius: 11px;
  border-color: #dbe3f0;
  background: #fff;
}
.input:focus, select:focus, textarea:focus {
  border-color: #818cf8;
  box-shadow: 0 0 0 3px rgba(99,102,241,.12);
}
.table-wrap { overflow: auto; }
.table { border-collapse: separate; border-spacing: 0; }
.table thead th {
  position: sticky;
  top: 0;
  z-index: 1;
  color: #475569;
  background: #f1f5f9;
  font-weight: 800;
}
.table tbody tr { transition: background .15s ease; }
.table tbody tr:hover { background: #f8faff; }
.badge { border-radius: 999px; font-weight: 750; }
.empty {
  padding: 28px 16px;
  border: 1px dashed #cbd5e1;
  border-radius: 14px;
  color: #64748b;
  background: #f8fafc;
  text-align: center;
}
@media (max-width: 760px) {
  .topbar__dashboard { min-height: 38px; padding-inline: 10px; }
  .topbar__dashboard span:last-child { font-size: .78rem; }
  .stat-grid { grid-template-columns: repeat(2,minmax(0,1fr)); gap: 10px; }
  .stat-card { padding: 14px; border-radius: 15px; }
  .card, .panel { padding: 15px; border-radius: 15px; }
}
@media (max-width: 380px) {
  .stat-grid { grid-template-columns: 1fr; }
}
CSS

/usr/bin/php8.3 -l resources/layouts/app.php
echo "Modern UI installed. Hard refresh the browser (Ctrl+Shift+R). Backup: $BACKUP"
