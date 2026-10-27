#!/usr/bin/env bash
# ساخت برنامه‌ی اندروید (APK) دفتر من با Capacitor
# این فایل را GitHub Actions اجرا می‌کند. لازم نیست خودت چیزی در آن عوض کنی.
set -euo pipefail

ROOT="$(pwd)"
OWNER="${GITHUB_REPOSITORY%%/*}"
REPO="${GITHUB_REPOSITORY##*/}"
SITE_URL="${SITE_URL:-https://$(echo "$OWNER" | tr 'A-Z' 'a-z').github.io/$REPO/}"
echo "آدرس سایت: $SITE_URL"

if [ -z "${MOCK_ANDROID:-}" ]; then
  rm -rf app
  mkdir app
  cd app
  npm init -y > /dev/null
  npm install --no-audit --no-fund @capacitor/core@6 @capacitor/cli@6 @capacitor/android@6 @capacitor/local-notifications@6
  npx cap telemetry off || true

  mkdir -p www
  cat > www/index.html <<'EOF'
<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>دفتر من</title></head>
<body style="background:#121315;color:#eee;font-family:sans-serif;text-align:center;padding-top:40vh">در حال باز شدن...</body></html>
EOF
  cat > www/offline.html <<EOF
<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>دفتر من</title></head>
<body style="background:#121315;color:#eee;font-family:sans-serif;text-align:center;padding:30vh 24px 0;line-height:2">
<h2>اینترنت وصل نیست</h2>
<p>برنامه را برای اولین بار به اینترنت وصل کن تا باز شود.<br>اعلان‌های ساعت‌دار بعد از آن بدون اینترنت هم کار می‌کنند.</p>
<p><a href="$SITE_URL" style="color:#f2c14e;font-size:18px">دوباره امتحان کن</a></p>
</body></html>
EOF
  cat > capacitor.config.json <<EOF
{
  "appId": "com.daftarman.app",
  "appName": "دفتر من",
  "webDir": "www",
  "server": {
    "url": "$SITE_URL",
    "cleartext": false,
    "errorPath": "offline.html"
  },
  "plugins": {
    "LocalNotifications": {
      "smallIcon": "ic_stat_notify",
      "iconColor": "#F2C14E"
    }
  }
}
EOF
  npx cap add android
  ANDROID_DIR="$PWD/android"
else
  ANDROID_DIR="$MOCK_ANDROID"
fi

# ---- دسترسی‌ها، صدای زنگ و آیکن ----
python3 -c "import PIL" 2>/dev/null || python3 -m pip install --quiet pillow || python3 -m pip install --quiet --break-system-packages pillow

python3 - "$ANDROID_DIR" "$ROOT" <<'PY'
import os, sys, math, wave, struct
from PIL import Image, ImageDraw

android, root = sys.argv[1], sys.argv[2]
main = os.path.join(android, 'app', 'src', 'main')
res = os.path.join(main, 'res')

# 1) دسترسی‌های لازم برای اعلان و الارم دقیق
mp = os.path.join(main, 'AndroidManifest.xml')
s = open(mp, encoding='utf-8').read()
need = ['POST_NOTIFICATIONS', 'USE_EXACT_ALARM', 'SCHEDULE_EXACT_ALARM',
        'RECEIVE_BOOT_COMPLETED', 'VIBRATE', 'WAKE_LOCK']
add = ''.join('    <uses-permission android:name="android.permission.%s" />\n' % x
              for x in need if 'android.permission.%s"' % x not in s)
if add and '<application' in s:
    s = s.replace('<application', add + '    <application', 1)
open(mp, 'w', encoding='utf-8').write(s)

# 2) صدای زنگ (۲۰ ثانیه)
raw = os.path.join(res, 'raw')
os.makedirs(raw, exist_ok=True)
sr = 16000
out = []
def beep(freq, dur, vol=0.55):
    n = int(sr * dur)
    for i in range(n):
        env = min(1.0, i / 120.0, (n - i) / 160.0)
        v = math.sin(2 * math.pi * freq * i / sr) + 0.35 * math.sin(2 * math.pi * freq * 2 * i / sr)
        out.append(int(32767 * vol * env * v / 1.35))
def rest(dur):
    out.extend([0] * int(sr * dur))
while len(out) < sr * 20:
    for _ in range(4):
        beep(1046, 0.11)
        rest(0.07)
    rest(0.55)
w = wave.open(os.path.join(raw, 'ring.wav'), 'wb')
w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
w.writeframes(b''.join(struct.pack('<h', x) for x in out))
w.close()

# 3) آیکن کوچک اعلان
dr = os.path.join(res, 'drawable')
os.makedirs(dr, exist_ok=True)
open(os.path.join(dr, 'ic_stat_notify.xml'), 'w', encoding='utf-8').write(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<vector xmlns:android="http://schemas.android.com/apk/res/android" '
    'android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">\n'
    '    <path android:fillColor="#FFFFFFFF" android:pathData="M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM10,17l-5,-5 1.41,-1.41L10,14.17l7.59,-7.59L19,8l-9,9z"/>\n'
    '</vector>\n')

# 4) آیکن برنامه
src_path = os.path.join(root, 'icon-512.png')
if os.path.exists(src_path):
    src = Image.open(src_path).convert('RGBA')
    dens = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
    for d, base in dens.items():
        folder = os.path.join(res, 'mipmap-' + d)
        os.makedirs(folder, exist_ok=True)
        S = base
        src.resize((S, S), Image.LANCZOS).save(os.path.join(folder, 'ic_launcher.png'))
        r = src.resize((S, S), Image.LANCZOS)
        mask = Image.new('L', (S, S), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, S - 1, S - 1], fill=255)
        r.putalpha(mask)
        r.save(os.path.join(folder, 'ic_launcher_round.png'))
        F = base * 108 // 48
        canvas = Image.new('RGBA', (F, F), (0, 0, 0, 0))
        inner = int(F * 0.62)
        canvas.paste(src.resize((inner, inner), Image.LANCZOS), ((F - inner) // 2, (F - inner) // 2))
        canvas.save(os.path.join(folder, 'ic_launcher_foreground.png'))
    any26 = os.path.join(res, 'mipmap-anydpi-v26')
    os.makedirs(any26, exist_ok=True)
    for name in ('ic_launcher', 'ic_launcher_round'):
        open(os.path.join(any26, name + '.xml'), 'w', encoding='utf-8').write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/daftar_bg"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '</adaptive-icon>\n')
    vals = os.path.join(res, 'values')
    os.makedirs(vals, exist_ok=True)
    open(os.path.join(vals, 'daftar_colors.xml'), 'w', encoding='utf-8').write(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="daftar_bg">#1C1D21</color>\n</resources>\n')
else:
    print('icon-512.png پیدا نشد؛ آیکن پیش‌فرض می‌ماند')
print('patch ok')
PY

if [ -n "${MOCK_ANDROID:-}" ]; then
  echo "حالت آزمایشی: همین‌جا تمام شد"
  exit 0
fi

# ---- کلید امضا (ثابت، تا بروزرسانی‌ها روی هم نصب شوند) ----
mkdir -p ~/.android
echo "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" | base64 -d > ~/.android/debug.keystore

npx cap sync android
cd android
chmod +x gradlew
./gradlew assembleDebug --no-daemon
cp app/build/outputs/apk/debug/app-debug.apk "$ROOT/daftar-man.apk"
echo "APK آماده شد: $ROOT/daftar-man.apk"
