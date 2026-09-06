#!/usr/bin/env python3
"""Honor synthesis pragmas before converting the hybrid SystemVerilog design."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--sv2v", type=Path, default=ROOT / "build/tools/sv2v")
parser.add_argument("--install-only", action="store_true")
parser.add_argument("sources", nargs="*", type=Path)
args = parser.parse_args()
converter = args.sv2v.resolve()
if not converter.exists():
    pin = json.loads((ROOT / "tools.lock.json").read_text())["downloads"]["sv2v"]
    archive = urllib.request.urlopen(pin["url"], timeout=60).read()
    if hashlib.sha256(archive).hexdigest() != pin["sha256"]:
        raise SystemExit("sv2v archive checksum mismatch")
    with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
        binary = next(name for name in bundle.namelist() if Path(name).name == "sv2v")
        converter.parent.mkdir(parents=True, exist_ok=True)
        converter.write_bytes(bundle.read(binary))
        converter.chmod(0o755)
if args.install_only:
    raise SystemExit(0)
if not args.sources:
    parser.error("source files are required")

sources = []
translate_off = re.compile(
    r"(?ms)^[ \t]*//\s*(?:pragma|synopsys|synthesis)\s+translate_off\b.*?"
    r"^[ \t]*//\s*(?:pragma|synopsys|synthesis)\s+translate_on[^\n]*"
)
for original in args.sources:
    destination = ROOT / "build/hybrid/sources" / original.resolve().relative_to(ROOT)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(translate_off.sub("", original.read_text()))
    sources.append(str(destination))
with (ROOT / "build/hybrid/core.v").open("w") as output:
    subprocess.run([str(converter), "-EAlways", "-DSYNTHESIS", "-DVERILATOR",
                    "-I" + str(ROOT), "-I" + str(ROOT / "third_party/common_cells/include"),
                    "--top=hybrid_top", *sources], stdout=output, check=True,
                   env=os.environ | {"GHCRTS": os.environ.get("GHCRTS", "-N2 -M2G")})

# Keep the native RTLIL top cache valid when only a child module changes.
converted = (ROOT / "build/hybrid/core.v").read_text()
top = re.search(r"(?ms)^module hybrid_top\b.*?^endmodule\b[^\n]*\n", converted)
if top is None:
    raise SystemExit("sv2v output is missing hybrid_top")
for name, text in (("top.v", top.group()),
                   ("components.v", converted[:top.start()] + converted[top.end():])):
    path = ROOT / "build/hybrid" / name
    if not path.exists() or path.read_text() != text:
        path.write_text(text)
