param(
    [string]$ReferenceId = "",
    [int]$Limit = 25
)

$ErrorActionPreference = "Stop"

if ($Limit -lt 1) {
    throw "Limit must be at least 1."
}

$remotePython = if ([string]::IsNullOrWhiteSpace($ReferenceId)) {
@"
import json
from pathlib import Path
from urllib import request

token = ""
for line in Path("/opt/court-relay/.env").read_text(encoding="utf-8").splitlines():
    if line.startswith("COURT_RELAY_TOKEN="):
        token = line.split("=", 1)[1].strip()
        break

req = request.Request(
    "http://127.0.0.1:8009/v1/feedback/submissions?limit=$Limit",
    headers={
        "x-court-relay-token": token,
        "Content-Type": "application/json",
    },
    method="GET",
)
with request.urlopen(req, timeout=20) as resp:
    payload = json.loads(resp.read().decode("utf-8"))
print(json.dumps(payload, indent=2))
"@
} else {
@"
import json
from pathlib import Path
from urllib import request, parse

token = ""
for line in Path("/opt/court-relay/.env").read_text(encoding="utf-8").splitlines():
    if line.startswith("COURT_RELAY_TOKEN="):
        token = line.split("=", 1)[1].strip()
        break

reference_id = parse.quote("$ReferenceId", safe="")
req = request.Request(
    f"http://127.0.0.1:8009/v1/feedback/submissions/{reference_id}",
    headers={
        "x-court-relay-token": token,
        "Content-Type": "application/json",
    },
    method="GET",
)
with request.urlopen(req, timeout=20) as resp:
    payload = json.loads(resp.read().decode("utf-8"))
print(json.dumps(payload, indent=2))
"@
}

$remotePython | ssh temple-droplet "cd /opt/court-relay && .venv/bin/python -"
