#!/bin/bash
# =============================================================================
# TianTian Ops - ports.sh
# Central managed port pool
# =============================================================================

TT_PORTS_STATE="${TT_HOME}/state/ports.json"

ports_init() {
    mkdir -p "$(dirname "$TT_PORTS_STATE")"
    if [ ! -f "$TT_PORTS_STATE" ]; then
        cat > "$TT_PORTS_STATE" <<'JSON'
{
  "version": "0.2",
  "ranges": {
    "wordpress": [8445, 8449],
    "toko": [8450, 8459],
    "sub2api": [8460, 8469],
    "komari": [8470, 8479],
    "network": [8480, 8499],
    "future": [8500, 8999]
  },
  "allocations": {}
}
JSON
    fi
}

ports_list() {
    ports_init
    print_header "端口池"
    python3 - "$TT_PORTS_STATE" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
print("  端口段:")
for name, span in data.get("ranges", {}).items():
    print(f"    {name:12s} {span[0]}-{span[1]}")
print("\n  已分配:")
alloc = data.get("allocations", {})
if not alloc:
    print("    (暂无)")
else:
    for project, ports in sorted(alloc.items()):
        rendered = ", ".join(f"{k}={v}" for k, v in sorted(ports.items()))
        print(f"    {project:12s} {rendered}")
PY
}

ports_allocate() {
    local project="$1"
    local group="${2:-future}"
    local key="${3:-main}"
    ports_init
    python3 - "$TT_PORTS_STATE" "$project" "$group" "$key" <<'PY'
import json, socket, sys
path, project, group, key = sys.argv[1:5]
with open(path) as f:
    data = json.load(f)
ranges = data.setdefault("ranges", {})
alloc = data.setdefault("allocations", {})
if group not in ranges:
    group = "future"
start, end = ranges[group]
project_ports = alloc.setdefault(project, {})
if key in project_ports:
    print(project_ports[key])
    raise SystemExit(0)
used = {int(v) for ports in alloc.values() for v in ports.values()}
def listening(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.2)
        return s.connect_ex(("127.0.0.1", port)) == 0
for port in range(start, end + 1):
    if port in used or listening(port):
        continue
    project_ports[key] = port
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(port)
    raise SystemExit(0)
print(f"ERROR: no free port in {group} range {start}-{end}", file=sys.stderr)
raise SystemExit(1)
PY
}

ports_suggest() {
    local project="$1"
    local group="${2:-future}"
    local key="${3:-main}"
    ports_init
    python3 - "$TT_PORTS_STATE" "$project" "$group" "$key" <<'PY'
import json, socket, sys
path, project, group, key = sys.argv[1:5]
with open(path) as f:
    data = json.load(f)
ranges = data.get("ranges", {})
alloc = data.get("allocations", {})
if project in alloc and key in alloc[project]:
    print(alloc[project][key])
    raise SystemExit(0)
if group not in ranges:
    group = "future"
start, end = ranges[group]
used = {int(v) for ports in alloc.values() for v in ports.values()}
def listening(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.2)
        return s.connect_ex(("127.0.0.1", port)) == 0
for port in range(start, end + 1):
    if port not in used and not listening(port):
        print(port)
        raise SystemExit(0)
raise SystemExit(1)
PY
}

ports_register() {
    local project="$1"
    local key="${2:-main}"
    local port="$3"
    ports_init
    python3 - "$TT_PORTS_STATE" "$project" "$key" "$port" <<'PY'
import json, sys
path, project, key, port = sys.argv[1:5]
port = int(port)
with open(path) as f:
    data = json.load(f)
alloc = data.setdefault("allocations", {})
for other_project, ports in alloc.items():
    for other_key, other_port in ports.items():
        if other_project != project and int(other_port) == port:
            print(f"ERROR: port {port} already allocated to {other_project}.{other_key}", file=sys.stderr)
            raise SystemExit(1)
alloc.setdefault(project, {})[key] = port
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print(port)
PY
}

ports_release_project() {
    local project="$1"
    ports_init
    python3 - "$TT_PORTS_STATE" "$project" <<'PY'
import json, sys
path, project = sys.argv[1:3]
with open(path) as f:
    data = json.load(f)
data.setdefault("allocations", {}).pop(project, None)
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
PY
}
