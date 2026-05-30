#!/usr/bin/env bash
# Download the community dashboards Grafana provisions on startup, and rewrite
# their datasource placeholder to our fixed Prometheus datasource UID so the
# panels resolve without manual import. Run this once before `docker compose up`.
set -euo pipefail
cd "$(dirname "$0")"

OUT="grafana/provisioning/dashboards/json"
mkdir -p "$OUT"

fetch() {
  id="$1"; name="$2"
  echo "Fetching dashboard ${id} -> ${name}.json"
  curl -fsSL "https://grafana.com/api/dashboards/${id}/revisions/latest/download" \
    | sed 's/${DS_PROMETHEUS}/prometheus/g' \
    > "${OUT}/${name}.json"
}

# Node Exporter Full (system: cpu, cores, temp, disk, ram, network)
fetch 1860 node-exporter-full
# cAdvisor (per-container cpu/mem/net/io)
fetch 14282 cadvisor

echo "Done. Community dashboards written to ${OUT}/"
