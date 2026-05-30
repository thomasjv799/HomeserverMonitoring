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
