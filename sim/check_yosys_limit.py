"""Exercise the synthesis guard without allocating a synthesis-sized design."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

guard = Path(__file__).resolve().parents[1] / "synth/limited_yosys.py"
with tempfile.TemporaryDirectory() as directory:
    executable = Path(directory) / "yosys"
    executable.write_text(f"#!{sys.executable}\nimport sys\nsys.exit(7)\n")
    executable.chmod(0o755)
    environment = dict(os.environ, PATH=directory + os.pathsep + os.environ["PATH"])
    command = [sys.executable, str(guard), "--memory-mb", "256"]
    assert subprocess.run(command, env=environment, timeout=10).returncode == 7
    executable.write_text(f"#!{sys.executable}\nimport time\nblocks=[]\n"
                          "while True:\n blocks.append(bytearray(8*1024*1024))\n time.sleep(0.2)\n")
    result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=15)
    assert result.returncode == 124 and "memory guard" in result.stderr, result
print("PASS synthesis guard: exit propagation and bounded memory stop")
