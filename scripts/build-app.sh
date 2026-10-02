#!/bin/zsh
# Baut "E-Invoice Generator.app" nach build/ – ohne Xcode-Projekt, direkt aus dem Swift-Paket.
set -e
cd "$(dirname "$0")/.."
swift build -c release --product InvoiceApp --arch arm64
APP="build/E-Invoice Generator.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/InvoiceApp "$APP/Contents/MacOS/E-Invoice Generator"
cp Config/config.json "$APP/Contents/Resources/config.json"

ICONSET_DIR="$APP/Contents/Resources/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
CUSTOM_ICON=""
for candidate in "$PWD/AppIcon.png" "$PWD/Assets/AppIcon.png" "$PWD/Resources/AppIcon.png" "$PWD/AppIcon.icns" "$PWD/Assets/AppIcon.icns" "$PWD/Resources/AppIcon.icns"; do
  if [[ -e "$candidate" ]]; then
    CUSTOM_ICON="$candidate"
    break
  fi
done

if [[ -n "$CUSTOM_ICON" && "$CUSTOM_ICON" == *.png ]]; then
  mkdir -p "$ICONSET_DIR"
  for size in 16 32 128 256 512 1024; do
    sips -Z "$size" "$CUSTOM_ICON" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null 2>&1 || true
    if [[ ! -f "$ICONSET_DIR/icon_${size}x${size}.png" ]]; then
      cp "$CUSTOM_ICON" "$ICONSET_DIR/icon_${size}x${size}.png"
    fi
  done
  iconutil -c icns "$ICONSET_DIR" -o "$APP/Contents/Resources/AppIcon.icns"
elif [[ -n "$CUSTOM_ICON" && "$CUSTOM_ICON" == *.icns ]]; then
  cp "$CUSTOM_ICON" "$APP/Contents/Resources/AppIcon.icns"
else
  mkdir -p "$ICONSET_DIR"
  python3 - "$ICONSET_DIR" <<'PY'
import os, sys, zlib, struct

out_dir = sys.argv[1]

def png_chunk(tag, data):
    return (
        struct.pack('!I', len(data))
        + tag
        + data
        + struct.pack('!I', 0xFFFFFFFF & __import__('zlib').crc32(tag + data) & 0xFFFFFFFF)
    )

def write_png(path, width, height, pixels):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            r, g, b, a = pixels[y][x]
            raw.extend((r, g, b, a))
    png = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('!IIBBBBB', width, height, 8, 6, 0, 0, 0)
    png += png_chunk(b'IHDR', ihdr)
    png += png_chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    png += png_chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)

def make_icon(size):
    bg = (19, 82, 146, 255)
    accent = (255, 196, 85, 255)
    white = (255, 255, 255, 255)
    pixels = [[bg for _ in range(size)] for _ in range(size)]
    for y in range(size):
        for x in range(size):
            dx = (x - size/2) / (size/2)
            dy = (y - size/2) / (size/2)
            dist = dx * dx + dy * dy
            if dist < 1.2:
                r = min(255, int(bg[0] + (255 - bg[0]) * (1.0 - dist / 1.2)))
                g = min(255, int(bg[1] + (255 - bg[1]) * (1.0 - dist / 1.2)))
                b = min(255, int(bg[2] + (255 - bg[2]) * (1.0 - dist / 1.2)))
                pixels[y][x] = (r, g, b, 255)
    margin = int(size * 0.18)
    bar_w = int(size * 0.18)
    bar_h = int(size * 0.12)
    x0 = int(size * 0.28)
    x1 = int(size * 0.7)
    for y in range(size):
        for x in range(size):
            if x >= x0 and x <= x1:
                if x == x0 or x == x1 or y in range(margin, margin + bar_h) or y in range(size//2 - bar_h//2, size//2 + bar_h//2) or y in range(size - margin - bar_h, size - margin):
                    pixels[y][x] = white
            if x >= x0 and x <= x0 + bar_w:
                for yy in range(size):
                    if yy in range(margin, margin + bar_h) or yy in range(size//2 - bar_h//2, size//2 + bar_h//2) or yy in range(size - margin - bar_h, size - margin):
                        pixels[yy][x] = white
    for y in range(size):
        for x in range(int(size*0.78), size):
            if y % 2 == 0:
                pixels[y][x] = accent
    return pixels

sizes = [16, 32, 128, 256, 512, 1024]
for s in sizes:
    pixels = make_icon(s)
    write_png(os.path.join(out_dir, f'icon_{s}x{s}.png'), s, s, pixels)
PY
  iconutil -c icns "$ICONSET_DIR" -o "$APP/Contents/Resources/AppIcon.icns"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>E-Invoice Generator</string>
  <key>CFBundleDisplayName</key><string>E-Invoice Generator</string>
  <key>CFBundleIdentifier</key><string>de.zweibruecken-ip.e-invoice-generator</string>
  <key>CFBundleExecutable</key><string>E-Invoice Generator</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>CFBundleVersion</key><string>0.2</string>
  <key>CFBundleDevelopmentRegion</key><string>de</string>
  <key>CFBundleGetInfoString</key><string>E-Invoice Generator 0.2 • Patentanwaltskanzlei Zweibrücken IP • https://zweibruecken-ip.de</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Patentanwaltskanzlei Zweibrücken IP • https://zweibruecken-ip.de</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>PDF document</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>pdf</string>
      </array>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.adobe.pdf</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Fertig: $APP"
