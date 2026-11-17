"""Run all self-checking tests. Supports IVERILOG/VVP executable overrides."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
build = root / "build"
build.mkdir(exist_ok=True)
subprocess.run([sys.executable, str(root / "scripts/generate_vectors.py")], check=True)
sources = [str(p.relative_to(root)) for p in sorted((root / "rtl").glob("*.sv"))]
compiler = os.environ.get("IVERILOG", "iverilog")
runtime = os.environ.get("VVP", "vvp")
backend = ["-B", os.environ["IVERILOG_BACKEND"]] if "IVERILOG_BACKEND" in os.environ else []
logs = []
for top in ("tb_axi_spi", "tb_de2_demo", "tb_boundaries"):
    output = build / (top + ".vvp")
    subprocess.run([compiler, *backend, "-g2012", "-Wall", "-s", top, "-o", str(output), *sources, f"tb/{top}.sv"], cwd=root, check=True)
    result = subprocess.run([runtime, str(output)], cwd=root, text=True, capture_output=True)
    print(result.stdout, end="")
    logs.append(result.stdout + result.stderr)
    (build / "regression.log").write_text("".join(logs))
    if result.returncode or "PASS:" not in result.stdout:
        raise SystemExit(f"FAILED {top}: {result.stderr}")
print("REGRESSION PASS (3 testbenches)")
