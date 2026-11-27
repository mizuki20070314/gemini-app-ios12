import os, json, math, zlib, struct

# Pure-Python PNG generator (zero external dependencies) for Gemini 4-point star AppIcon
def write_png(path, width, height, rgba_bytes):
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw.extend(rgba_bytes[y*stride:(y+1)*stride])
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)

def render_icon(size):
    buf = bytearray(size * size * 4)
    cx = (size - 1) / 2.0
    cy = (size - 1) / 2.0
    r_star = size * 0.36
    for y in range(size):
        ny = (y - cy) / (size * 0.5)
        for x in range(size):
            nx = (x - cx) / (size * 0.5)
            # Deep midnight-to-indigo background gradient
            t = (nx * 0.5 + ny * 0.5 + 1.0) * 0.5
            bg_r = 16 + 18 * t
            bg_g = 22 + 24 * t
            bg_b = 46 + 44 * t

            # Soft radial glow behind sparkle
            dist = math.hypot(nx, ny)
            glow = max(0.0, 1.0 - dist / 0.85) ** 2.2
            bg_r += 48 * glow
            bg_g += 95 * glow
            bg_b += 195 * glow

            # 4-point astroid / superellipse star: |x|^0.55 + |y|^0.55 <= r^0.55
            dx = abs(x - cx) / r_star
            dy = abs(y - cy) / r_star
            val = (dx ** 0.55) + (dy ** 0.55)
            aa = max(0.0, min(1.0, (1.0 - val) * (size * 0.055) + 0.5))

            if aa > 0.0:
                # Gemini sparkle gradient: Google Blue -> Periwinkle -> Violet -> Rose
                gt = max(0.0, min(1.0, (nx + ny + 0.8) / 1.6))
                if gt < 0.5:
                    u = gt * 2.0
                    sr = 66 * (1 - u) + 155 * u
                    sg = 133 * (1 - u) + 114 * u
                    sb = 244 * (1 - u) + 203 * u
                else:
                    u = (gt - 0.5) * 2.0
                    sr = 155 * (1 - u) + 217 * u
                    sg = 114 * (1 - u) + 101 * u
                    sb = 203 * (1 - u) + 112 * u
                # White core highlight
                core = max(0.0, 1.0 - dist / 0.35) ** 2.0
                sr = sr * (1 - core * 0.55) + 255 * (core * 0.55)
                sg = sg * (1 - core * 0.55) + 255 * (core * 0.55)
                sb = sb * (1 - core * 0.55) + 255 * (core * 0.55)

                r = bg_r * (1 - aa) + sr * aa
                g = bg_g * (1 - aa) + sg * aa
                b = bg_b * (1 - aa) + sb * aa
            else:
                r, g, b = bg_r, bg_g, bg_b

            idx = (y * size + x) * 4
            buf[idx] = max(0, min(255, int(r)))
            buf[idx + 1] = max(0, min(255, int(g)))
            buf[idx + 2] = max(0, min(255, int(b)))
            buf[idx + 3] = 255
    return bytes(buf)

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
assets = os.path.join(root, "GeminiApp", "Resources", "Assets.xcassets")
appicon = os.path.join(assets, "AppIcon.appiconset")
os.makedirs(appicon, exist_ok=True)

with open(os.path.join(assets, "Contents.json"), "w") as f:
    json.dump({"info": {"version": 1, "author": "xcode"}}, f, indent=2)

specs = [
    ("iphone", "20x20", "2x", 40),
    ("iphone", "20x20", "3x", 60),
    ("iphone", "29x29", "2x", 58),
    ("iphone", "29x29", "3x", 87),
    ("iphone", "40x40", "2x", 80),
    ("iphone", "40x40", "3x", 120),
    ("iphone", "60x60", "2x", 120),
    ("iphone", "60x60", "3x", 180),
    ("ipad", "20x20", "1x", 20),
    ("ipad", "20x20", "2x", 40),
    ("ipad", "29x29", "1x", 29),
    ("ipad", "29x29", "2x", 58),
    ("ipad", "40x40", "1x", 40),
    ("ipad", "40x40", "2x", 80),
    ("ipad", "76x76", "1x", 76),
    ("ipad", "76x76", "2x", 152),
    ("ipad", "83.5x83.5", "2x", 167),
    ("ios-marketing", "1024x1024", "1x", 1024),
]

images = []
cache = {}
for idiom, size_str, scale, px in specs:
    fname = f"icon_{px}.png"
    if px not in cache:
        write_png(os.path.join(appicon, fname), px, px, render_icon(px))
        cache[px] = True
    images.append({"idiom": idiom, "size": size_str, "scale": scale, "filename": fname})

with open(os.path.join(appicon, "Contents.json"), "w") as f:
    json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, f, indent=2)

print(f"Generated {len(cache)} Gemini AppIcon PNGs in {appicon}")
