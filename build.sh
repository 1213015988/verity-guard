#!/usr/bin/env bash
# 打包模块 zip：./build.sh
set -eu
cd "$(dirname "$0")"
ver=$(sed -n 's/^version=//p' module/module.prop)
mkdir -p dist
python3 - "$ver" <<'PY'
import os, sys, zipfile, stat
ver = sys.argv[1]
out = f"dist/verity-guard-v{ver}.zip"
files = []
for root, dirs, fs in os.walk("module"):
    dirs.sort()
    for f in sorted(fs):
        files.append(os.path.relpath(os.path.join(root, f), "module"))
files.sort(key=lambda p: (not p.endswith("module.prop"), p))
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for f in files:
        zi = zipfile.ZipInfo(f, date_time=(2026, 1, 1, 0, 0, 0))
        zi.compress_type = zipfile.ZIP_DEFLATED
        exe = f.endswith(".sh") or f in ("vgkey", "vg") or f.endswith("update-binary")
        zi.external_attr = (stat.S_IFREG | (0o755 if exe else 0o644)) << 16
        path = os.path.join("module", f)
        z.writestr(zi, open(path, "rb").read())
print("built", out, os.path.getsize(out), "bytes,", len(files), "files")
PY
