# Grafana Monitoring Stack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a self-contained Grafana + Prometheus + Loki docker-compose stack (in `grafana-stack/`) to the home server, giving a system-overview dashboard, a per-container logs dashboard, and Telegram alerts — running alongside the untouched Netdata stack.

**Architecture:** A second docker-compose project, independent of Netdata, on non-conflicting ports. Prometheus scrapes node_exporter (system), cAdvisor (containers), and the Docker daemon (container states/restarts). Grafana Alloy auto-discovers containers and ships their logs to Loki. Grafana renders provisioned dashboards and alert rules, reusing the existing Telegram bot.

**Tech Stack:** Docker Compose, Grafana, Prometheus, Loki, Grafana Alloy, prometheus node_exporter, cAdvisor, Telegram Bot API.

---

## File Structure

All new files live under `grafana-stack/`:

| File | Responsibility |
|---|---|
| `docker-compose.yml` | The six services + named volumes + bridge network. |
| `.env.example` | Grafana admin creds + `TG_BOT_TOKEN` / `TG_CHAT_ID`. |
| `prometheus/prometheus.yml` | Scrape configs (node_exporter, cAdvisor, dockerd, self). |
| `loki/loki-config.yml` | Single-binary Loki, filesystem storage. |
| `alloy/config.alloy` | Docker log discovery → Loki. |
| `grafana/provisioning/datasources/datasources.yml` | Prometheus + Loki datasources (fixed UIDs). |
| `grafana/provisioning/dashboards/dashboards.yml` | Dashboard file provider. |
| `grafana/provisioning/dashboards/json/logs.json` | Custom logs dashboard (panel repeats per container). |
| `grafana/provisioning/dashboards/json/docker-overview.json` | Custom: containers running / stopped / restart signal. |
| `grafana/provisioning/dashboards/json/node-exporter-full.json` | Community 1860 (fetched by script). |
| `grafana/provisioning/dashboards/json/cadvisor.json` | Community 14282 (fetched by script). |
| `grafana/provisioning/alerting/contact-points.yml` | Telegram contact point. |
| `grafana/provisioning/alerting/policies.yml` | Route everything to Telegram. |
| `grafana/provisioning/alerting/rules.yml` | Log-error-spike + container-crash-loop rules. |
| `fetch-dashboards.sh` | Downloads the two community dashboards and fixes their datasource UID. |
| `README.md` | Host step (dockerd metrics), bring-up, URLs, verification. |

> Note: `.gitignore` already ignores `grafana-stack/.env` and `grafana-stack/data/` (added when the spec was committed). The community dashboard JSON files are produced by `fetch-dashboards.sh` and are git-ignored runtime artifacts; the custom JSON files are committed.

---

### Task 1: Scaffold the stack directory and secrets template

**Files:**
- Create: `grafana-stack/.env.example`
- Modify: `.gitignore`
- Create: `grafana-stack/.gitignore`

- [ ] **Step 1: Create `grafana-stack/.env.example`**

```dotenv
# Grafana admin login
GF_ADMIN_USER=admin
GF_ADMIN_PASSWORD=changeme-pick-a-strong-one

# Telegram alerts — reuse the same bot/chat as the Netdata stack.
# (Distinct names from Netdata internals; see the root README Telegram steps.)
TG_BOT_TOKEN=123456789:AAExampleReplaceMeWithYourRealToken
TG_CHAT_ID=123456789
```

- [ ] **Step 2: Ignore the fetched community dashboards**

Create `grafana-stack/.gitignore`:

```gitignore
# Secrets and runtime data (also covered by root .gitignore)
.env
data/

# Community dashboards are fetched by fetch-dashboards.sh, not committed
grafana/provisioning/dashboards/json/node-exporter-full.json
grafana/provisioning/dashboards/json/cadvisor.json
```

- [ ] **Step 3: Confirm root .gitignore already covers the stack secrets**

Run:

```bash
grep -n 'grafana-stack' .gitignore
```
Expected: shows `grafana-stack/.env` and `grafana-stack/data/`. If missing, append them:
```bash
printf '%s\n' 'grafana-stack/.env' 'grafana-stack/data/' >> .gitignore
```

- [ ] **Step 4: Commit**

```bash
git add grafana-stack/.env.example grafana-stack/.gitignore .gitignore
git commit -m "chore: scaffold grafana-stack directory and secrets template"
```

---

### Task 2: Docker Compose stack

**Files:**
- Create: `grafana-stack/docker-compose.yml`

- [ ] **Step 1: Write `grafana-stack/docker-compose.yml`**

```yaml
name: grafana-stack

services:
  grafana:
    image: grafana/grafana:latest
    container_name: gs-grafana
    restart: unless-stopped
    env_file: .env
    environment:
      - GF_SECURITY_ADMIN_USER=${GF_ADMIN_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GF_ADMIN_PASSWORD}
      - GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/etc/grafana/provisioning/dashboards/json/node-exporter-full.json
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - grafana-data:/var/lib/grafana
    ports:
      - "3000:3000"
    depends_on:
      - prometheus
      - loki

  prometheus:
    image: prom/prometheus:latest
    container_name: gs-prometheus
    restart: unless-stopped
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.retention.time=30d
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    extra_hosts:
      - "host.docker.internal:host-gateway"
    ports:
      - "9090:9090"

  loki:
    image: grafana/loki:latest
    container_name: gs-loki
    restart: unless-stopped
    command: -config.file=/etc/loki/loki-config.yml
    volumes:
      - ./loki/loki-config.yml:/etc/loki/loki-config.yml:ro
      - loki-data:/loki
    ports:
      - "3100:3100"

  alloy:
    image: grafana/alloy:latest
    container_name: gs-alloy
    restart: unless-stopped
    command:
      - run
      - /etc/alloy/config.alloy
      - --server.http.listen-addr=0.0.0.0:12345
      - --storage.path=/var/lib/alloy/data
    volumes:
      - ./alloy/config.alloy:/etc/alloy/config.alloy:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - alloy-data:/var/lib/alloy/data
    ports:
      - "12345:12345"

  node-exporter:
    image: quay.io/prometheus/node-exporter:latest
    container_name: gs-node-exporter
    restart: unless-stopped
    command:
      - --path.rootfs=/host
      - --collector.hwmon
    pid: host
    volumes:
      - /:/host:ro,rslave
    ports:
      - "9100:9100"

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: gs-cadvisor
    restart: unless-stopped
    privileged: true
    devices:
      - /dev/kmsg
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    ports:
      - "8080:8080"

volumes:
  grafana-data:
  prometheus-data:
  loki-data:
  alloy-data:
```

- [ ] **Step 2: Validate compose syntax**

```bash
cd grafana-stack
cp .env.example .env
docker compose config >/dev/null && echo "compose OK"
rm .env
cd ..
```
Expected: `compose OK`. (If Docker isn't installed locally, defer to the server.)

- [ ] **Step 3: Commit**

```bash
git add grafana-stack/docker-compose.yml
git commit -m "feat: grafana-stack compose (grafana, prometheus, loki, alloy, exporters)"
```

---

### Task 3: Prometheus scrape config

**Files:**
- Create: `grafana-stack/prometheus/prometheus.yml`

- [ ] **Step 1: Write `grafana-stack/prometheus/prometheus.yml`**

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: node
    static_configs:
      - targets: ["node-exporter:9100"]

  - job_name: cadvisor
    static_configs:
      - targets: ["cadvisor:8080"]

  # Docker daemon metrics (enabled on the host via /etc/docker/daemon.json).
  # Reached over the docker bridge gateway from inside this compose network.
  - job_name: docker
    static_configs:
      - targets: ["host.docker.internal:9323"]
```

- [ ] **Step 2: Validate YAML parses**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('grafana-stack/prometheus/prometheus.yml')); print('yaml OK')"
```
Expected: `yaml OK`.

- [ ] **Step 3: Commit**

```bash
git add grafana-stack/prometheus/prometheus.yml
git commit -m "feat: prometheus scrape config for node, cadvisor, dockerd"
```

---

### Task 4: Loki config

**Files:**
- Create: `grafana-stack/loki/loki-config.yml`

- [ ] **Step 1: Write `grafana-stack/loki/loki-config.yml`**

```yaml
auth_enabled: false

server:
  http_listen_port: 3100

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 168h
  reject_old_samples: true
  reject_old_samples_max_age: 168h

compactor:
  working_directory: /loki/compactor
  retention_enabled: true
  delete_request_store: filesystem
```

- [ ] **Step 2: Validate YAML parses**

```bash
python3 -c "import yaml; yaml.safe_load(open('grafana-stack/loki/loki-config.yml')); print('yaml OK')"
```
Expected: `yaml OK`.

- [ ] **Step 3: Commit**

```bash
git add grafana-stack/loki/loki-config.yml
git commit -m "feat: single-binary loki config with 7-day retention"
```

---

### Task 5: Alloy log collection

**Files:**
- Create: `grafana-stack/alloy/config.alloy`

- [ ] **Step 1: Write `grafana-stack/alloy/config.alloy`**

```alloy
// Discover all running Docker containers via the Docker socket.
discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

// Turn the Docker container name (/foo) into a clean `container` label.
discovery.relabel "containers" {
  targets = discovery.docker.containers.targets

  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/(.*)"
    target_label  = "container"
  }
}

// Tail each discovered container's logs and forward to Loki.
loki.source.docker "containers" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.relabel.containers.output
  forward_to = [loki.write.default.receiver]
}

loki.write "default" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```

- [ ] **Step 2: Sanity-check the file exists and is non-empty**

```bash
test -s grafana-stack/alloy/config.alloy && echo "alloy config present"
```
Expected: `alloy config present`. (Full validation happens when Alloy starts on the server.)

- [ ] **Step 3: Commit**

```bash
git add grafana-stack/alloy/config.alloy
git commit -m "feat: alloy config to ship all container logs to loki"
```

---

### Task 6: Grafana datasources and dashboard provider

**Files:**
- Create: `grafana-stack/grafana/provisioning/datasources/datasources.yml`
- Create: `grafana-stack/grafana/provisioning/dashboards/dashboards.yml`

- [ ] **Step 1: Write `grafana-stack/grafana/provisioning/datasources/datasources.yml`**

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true

  - name: Loki
    uid: loki
    type: loki
    access: proxy
    url: http://loki:3100
```

- [ ] **Step 2: Write `grafana-stack/grafana/provisioning/dashboards/dashboards.yml`**

```yaml
apiVersion: 1

providers:
  - name: default
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards/json
      foldersFromFilesStructure: false
```

- [ ] **Step 3: Validate both parse**

```bash
python3 -c "import yaml; yaml.safe_load(open('grafana-stack/grafana/provisioning/datasources/datasources.yml')); yaml.safe_load(open('grafana-stack/grafana/provisioning/dashboards/dashboards.yml')); print('yaml OK')"
```
Expected: `yaml OK`.

- [ ] **Step 4: Commit**

```bash
git add grafana-stack/grafana/provisioning/datasources/datasources.yml grafana-stack/grafana/provisioning/dashboards/dashboards.yml
git commit -m "feat: provision grafana prometheus+loki datasources and dashboard loader"
```

---

### Task 7: Fetch community dashboards

**Files:**
- Create: `grafana-stack/fetch-dashboards.sh`

- [ ] **Step 1: Write `grafana-stack/fetch-dashboards.sh`**

```bash
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
```

- [ ] **Step 2: Make it executable and commit**

```bash
chmod +x grafana-stack/fetch-dashboards.sh
git add grafana-stack/fetch-dashboards.sh
git commit -m "feat: script to fetch+patch community grafana dashboards"
```

(Running it is part of the server bring-up in Task 12; it needs internet access.)

---

### Task 8: Custom logs dashboard

**Files:**
- Create: `grafana-stack/grafana/provisioning/dashboards/json/logs.json`

- [ ] **Step 1: Write `grafana-stack/grafana/provisioning/dashboards/json/logs.json`**

```json
{
  "uid": "container-logs",
  "title": "Container Logs",
  "tags": ["logs"],
  "timezone": "browser",
  "schemaVersion": 39,
  "version": 1,
  "time": { "from": "now-1h", "to": "now" },
  "templating": {
    "list": [
      {
        "name": "container",
        "type": "query",
        "datasource": { "type": "loki", "uid": "loki" },
        "query": { "label": "container", "stream": "", "type": 1 },
        "definition": "label_values(container)",
        "includeAll": true,
        "multi": true,
        "allValue": ".+",
        "refresh": 2,
        "sort": 1,
        "current": { "text": "All", "value": "$__all" }
      }
    ]
  },
  "panels": [
    {
      "id": 1,
      "type": "logs",
      "title": "Logs — $container",
      "datasource": { "type": "loki", "uid": "loki" },
      "repeat": "container",
      "repeatDirection": "v",
      "gridPos": { "h": 10, "w": 24, "x": 0, "y": 0 },
      "options": {
        "showTime": true,
        "wrapLogMessage": true,
        "enableLogDetails": true,
        "dedupStrategy": "none",
        "sortOrder": "Descending"
      },
      "targets": [
        {
          "refId": "A",
          "datasource": { "type": "loki", "uid": "loki" },
          "expr": "{container=\"$container\"}"
        }
      ]
    }
  ]
}
```

- [ ] **Step 2: Validate JSON parses**

```bash
python3 -c "import json; json.load(open('grafana-stack/grafana/provisioning/dashboards/json/logs.json')); print('json OK')"
```
Expected: `json OK`.

- [ ] **Step 3: Commit**

```bash
git add grafana-stack/grafana/provisioning/dashboards/json/logs.json
git commit -m "feat: custom logs dashboard with per-container repeated panels"
```

---

### Task 9: Custom Docker overview dashboard

**Files:**
- Create: `grafana-stack/grafana/provisioning/dashboards/json/docker-overview.json`

- [ ] **Step 1: Write `grafana-stack/grafana/provisioning/dashboards/json/docker-overview.json`**

```json
{
  "uid": "docker-overview",
  "title": "Docker Overview",
  "tags": ["docker"],
  "timezone": "browser",
  "schemaVersion": 39,
  "version": 1,
  "time": { "from": "now-6h", "to": "now" },
  "panels": [
    {
      "id": 1,
      "type": "stat",
      "title": "Containers running",
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "gridPos": { "h": 6, "w": 6, "x": 0, "y": 0 },
      "options": { "reduceOptions": { "calcs": ["lastNotNull"] }, "colorMode": "value" },
      "targets": [
        {
          "refId": "A",
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "expr": "engine_daemon_container_states_containers{state=\"running\"}"
        }
      ]
    },
    {
      "id": 2,
      "type": "stat",
      "title": "Containers stopped",
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "gridPos": { "h": 6, "w": 6, "x": 6, "y": 0 },
      "options": { "reduceOptions": { "calcs": ["lastNotNull"] }, "colorMode": "value" },
      "targets": [
        {
          "refId": "A",
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "expr": "engine_daemon_container_states_containers{state=\"stopped\"}"
        }
      ]
    },
    {
      "id": 3,
      "type": "stat",
      "title": "Container starts (last 10m) — high = crash loop",
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "gridPos": { "h": 6, "w": 12, "x": 12, "y": 0 },
      "options": { "reduceOptions": { "calcs": ["lastNotNull"] }, "colorMode": "value" },
      "targets": [
        {
          "refId": "A",
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "expr": "increase(engine_daemon_container_actions_seconds_count{action=\"start\"}[10m])"
        }
      ]
    },
    {
      "id": 4,
      "type": "timeseries",
      "title": "Container states over time",
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "gridPos": { "h": 9, "w": 24, "x": 0, "y": 6 },
      "targets": [
        {
          "refId": "A",
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "expr": "engine_daemon_container_states_containers",
          "legendFormat": "{{state}}"
        }
      ]
    },
    {
      "id": 5,
      "type": "table",
      "title": "Per-container uptime (low = recently (re)started)",
      "datasource": { "type": "prometheus", "uid": "prometheus" },
      "gridPos": { "h": 10, "w": 24, "x": 0, "y": 15 },
      "options": { "showHeader": true },
      "targets": [
        {
          "refId": "A",
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "expr": "time() - container_start_time_seconds{name!=\"\"}",
          "legendFormat": "{{name}}",
          "format": "table",
          "instant": true
        }
      ]
    }
  ]
}
```

- [ ] **Step 2: Validate JSON parses**

```bash
python3 -c "import json; json.load(open('grafana-stack/grafana/provisioning/dashboards/json/docker-overview.json')); print('json OK')"
```
Expected: `json OK`.

- [ ] **Step 3: Commit**

```bash
git add grafana-stack/grafana/provisioning/dashboards/json/docker-overview.json
git commit -m "feat: docker overview dashboard (running/stopped/restart signals)"
```

---

### Task 10: Telegram alerting (contact point, policy, rules)

**Files:**
- Create: `grafana-stack/grafana/provisioning/alerting/contact-points.yml`
- Create: `grafana-stack/grafana/provisioning/alerting/policies.yml`
- Create: `grafana-stack/grafana/provisioning/alerting/rules.yml`

- [ ] **Step 1: Write `grafana-stack/grafana/provisioning/alerting/contact-points.yml`**

Grafana expands `$__env{...}` in provisioning files, so the secrets stay in `.env`:

```yaml
apiVersion: 1

contactPoints:
  - orgId: 1
    name: telegram
    receivers:
      - uid: telegram-1
        type: telegram
        settings:
          bottoken: $__env{TG_BOT_TOKEN}
          chatid: "$__env{TG_CHAT_ID}"
        disableResolveMessage: false
```

- [ ] **Step 2: Write `grafana-stack/grafana/provisioning/alerting/policies.yml`**

```yaml
apiVersion: 1

policies:
  - orgId: 1
    receiver: telegram
    group_by: ["alertname"]
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 4h
```

- [ ] **Step 3: Write `grafana-stack/grafana/provisioning/alerting/rules.yml`**

```yaml
apiVersion: 1

groups:
  - orgId: 1
    name: homeserver
    folder: Alerts
    interval: 1m
    rules:
      - uid: log-error-spike
        title: Log error spike
        condition: C
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: High rate of error/panic/fatal log lines across containers
        noDataState: OK
        execErrState: OK
        data:
          - refId: A
            relativeTimeRange: { from: 300, to: 0 }
            datasourceUid: loki
            model:
              refId: A
              expr: 'sum(count_over_time({container=~".+"} |~ "(?i)(error|panic|fatal)" [5m]))'
              queryType: instant
          - refId: C
            datasourceUid: __expr__
            model:
              refId: C
              type: threshold
              expression: A
              conditions:
                - evaluator: { type: gt, params: [20] }

      - uid: container-crash-loop
        title: Container crash-looping
        condition: C
        for: 0m
        labels:
          severity: critical
        annotations:
          summary: A container has restarted many times in the last 10 minutes
        noDataState: OK
        execErrState: OK
        data:
          - refId: A
            relativeTimeRange: { from: 600, to: 0 }
            datasourceUid: prometheus
            model:
              refId: A
              expr: 'increase(engine_daemon_container_actions_seconds_count{action="start"}[10m])'
              instant: true
          - refId: C
            datasourceUid: __expr__
            model:
              refId: C
              type: threshold
              expression: A
              conditions:
                - evaluator: { type: gt, params: [3] }
```

- [ ] **Step 4: Validate all three parse**

```bash
python3 -c "import yaml,glob; [yaml.safe_load(open(f)) for f in glob.glob('grafana-stack/grafana/provisioning/alerting/*.yml')]; print('yaml OK')"
```
Expected: `yaml OK`.

- [ ] **Step 5: Commit**

```bash
git add grafana-stack/grafana/provisioning/alerting/
git commit -m "feat: grafana telegram alerts — log error spike + container crash loop"
```

---

### Task 11: README and host prerequisite

**Files:**
- Create: `grafana-stack/README.md`

- [ ] **Step 1: Write `grafana-stack/README.md`**

````markdown
# Grafana Monitoring Stack

A second monitoring stack (Grafana + Prometheus + Loki) that runs alongside the
Netdata stack in this repo. Gives a system-overview dashboard, a per-container
logs dashboard, and Telegram alerts.

| URL | What |
|-----|------|
| http://<server-ip>:3000 | Grafana (dashboards + alerts) |
| http://<server-ip>:9090 | Prometheus (raw metrics, optional) |

## 1. Host prerequisite — enable Docker daemon metrics

This gives the "containers running / stopped / restart" numbers. Edit
`/etc/docker/daemon.json` (create it if absent) to include:

```json
{
  "metrics-addr": "0.0.0.0:9323",
  "experimental": true
}
```
Then restart Docker (this briefly bounces all containers, including Netdata):
```bash
sudo systemctl restart docker
```
Verify metrics are exposed:
```bash
curl -s http://localhost:9323/metrics | head -n 5
```

> Note: `0.0.0.0:9323` exposes daemon metrics on your LAN. On a trusted home
> network this is fine; tighten to the docker bridge IP if you prefer.

## 2. Configure secrets

```bash
cd grafana-stack
cp .env.example .env
```
Edit `.env`: set a strong `GF_ADMIN_PASSWORD`, and set `TG_BOT_TOKEN` / `TG_CHAT_ID`
to the same values used by the Netdata stack (`../.env`).

## 3. Fetch the community dashboards

```bash
./fetch-dashboards.sh
```
This downloads Node Exporter Full + cAdvisor dashboards into the provisioning
folder (needs internet access).

## 4. Bring up the stack

```bash
docker compose up -d
docker compose ps
```
Open **http://<server-ip>:3000**, log in with your admin credentials. The home
page is the system overview (Node Exporter Full). Other dashboards: **cAdvisor**,
**Docker Overview**, **Container Logs**.

## 5. Verification checklist

- [ ] All six containers (`gs-*`) show running in `docker compose ps`.
- [ ] Grafana home shows live CPU / per-core / temperature / disk / RAM.
- [ ] **Docker Overview** shows the running-container count and restart signal.
- [ ] **Container Logs** shows one panel per running container with live logs.
- [ ] Prometheus targets are all UP: open
      `http://<server-ip>:9090/targets` — `node`, `cadvisor`, `docker` all green.
- [ ] Telegram test: temporarily lower the crash-loop rule, or emit error logs:
      ```bash
      docker run --rm alpine sh -c 'for i in $(seq 1 50); do echo "ERROR test $i"; done'
      ```
      A "Log error spike" alert should reach Telegram within a few minutes.

## Updating

```bash
docker compose pull && docker compose up -d
```

## Notes
- Independent of the Netdata stack — start/stop/update either without affecting
  the other. Ports are chosen to not collide (`:19999`/`:9798` are Netdata's).
- Reachable over Tailscale at `http://<tailscale-ip>:3000`.
- The Grafana container may take ownership of `./grafana/...` files; if a future
  `git pull` fails with "Permission denied", run
  `sudo chown -R $(id -u):$(id -g) grafana-stack` first.
````

- [ ] **Step 2: Commit**

```bash
git add grafana-stack/README.md
git commit -m "docs: grafana-stack setup, host metrics step, verification"
```

---

### Task 12: Server bring-up and validation

Runs on the Mac mini after the repo is pulled and `grafana-stack/.env` is filled in.

- [ ] **Step 1: Enable Docker daemon metrics** (README section 1), then `sudo systemctl restart docker` and confirm `curl -s http://localhost:9323/metrics | head`.

- [ ] **Step 2: Configure and launch**

```bash
cd grafana-stack
cp .env.example .env   # then edit: GF_ADMIN_PASSWORD, TG_BOT_TOKEN, TG_CHAT_ID
./fetch-dashboards.sh
docker compose config >/dev/null && echo "compose OK"
docker compose up -d
docker compose ps
```
Expected: `compose OK`, then all six `gs-*` containers running.

- [ ] **Step 3: Walk the README verification checklist** (dashboards populated, Prometheus targets UP, Telegram alert arrives).

- [ ] **Step 4: Tag**

```bash
git tag -a grafana-stack-v1.0 -m "Working grafana+prometheus+loki stack"
```

---

## Notes for the implementer

- Infra/config project: "tests" are the `docker compose config`, YAML/JSON parse
  checks, and the README verification checklist on real hardware. No unit tests.
- Never commit `grafana-stack/.env`. The Telegram secrets live only there; the
  alerting contact point reads them via Grafana's `$__env{...}` provisioning
  interpolation.
- The two community dashboard JSON files are fetched, not committed (git-ignored).
- The Grafana `$__env{}` interpolation for the Telegram contact point is the most
  uncertain piece — verify the test alert actually arrives (Step 3). If the token
  doesn't resolve, the fallback is to inline the values into
  `contact-points.yml` on the server (kept out of git) — but try the env form first.
