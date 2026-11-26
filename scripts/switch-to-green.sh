#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
p = Path("kubernetes/base/httproute.yaml")
s = p.read_text()
s = s.replace("name: green\n          port: 80\n          weight: 0", "name: green\n          port: 80\n          weight: 100")
s = s.replace("name: blue\n          port: 80\n          weight: 100", "name: blue\n          port: 80\n          weight: 0")
p.write_text(s)
PY
echo "HTTPRoute now sends 100% traffic to Green. Commit and push this change for Argo CD to sync."
