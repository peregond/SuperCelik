#!/usr/bin/env python3
"""Files for delta updates of the Linux app.

  python3 scripts/make-linux-delta.py <published folder> <output prefix> <version>

writes <prefix>.zip (every file as its own deflated entry, so a client can fetch single entries with HTTP range requests)
and <prefix>.manifest.json (path, SHA-256, size and executable bit of every file). The app downloads only the manifest,
compares it with the installed files and then reads from the .zip just the entries whose SHA-256 differs.
"""
import hashlib, json, os, sys, zipfile

pub, prefix, version = sys.argv[1], sys.argv[2], sys.argv[3]
files = []
for root, _, names in os.walk(pub):
    for n in names:
        full = os.path.join(root, n)
        rel = os.path.relpath(full, pub).replace(os.sep, "/")
        files.append((rel, full))
files.sort()

manifest = {"version": version, "files": []}
with zipfile.ZipFile(prefix + ".zip", "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for rel, full in files:
        h = hashlib.sha256()
        with open(full, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        manifest["files"].append({"p": rel, "s": h.hexdigest(), "n": os.path.getsize(full), "x": bool(os.stat(full).st_mode & 0o111)})
        z.write(full, rel)
with open(prefix + ".manifest.json", "w") as f:
    json.dump(manifest, f, separators=(",", ":"))
print(f"{len(files)} files -> {prefix}.zip, {prefix}.manifest.json")
