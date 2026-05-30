# Home Server Monitoring — Design

**Date:** 2026-05-30
**Status:** Approved

## Goal

An always-on, visual dashboard for an old Mac mini running Ubuntu (home server),
showing system health, temperatures, running Docker containers, and internet
speed — with Telegram alerts and secure remote access. Designed to also monitor a
self-hosted PostgreSQL database once it is added.

## Approach

Assemble proven, free, open-source tools rather than building custom code. The
entire stack runs as Docker containers defined in a single `docker-compose.yml`,
so it comes up with one command and is easy to version-control and back up.

Chosen dashboard: **Netdata** (free, open-source agent). It provides a polished
real-time dashboard out of the box, auto-discovers system metrics, temperatures,
Docker containers, and PostgreSQL, and includes a built-in health/alerting engine.

Rejected alternative: Prometheus + Grafana. More flexible but significantly more
moving parts and config; overkill for a single home server whose primary goal is
"see how the box is doing visually." Can be added later if Netdata is outgrown
(Netdata can feed Grafana).

## Components

| Component | Role |
|---|---|
| **Netdata** | Core dashboard at `:19999`. Auto-collects CPU, RAM, disk, network, temperatures, and per-container Docker stats. Runs the Telegram alert engine. Will collect PostgreSQL metrics when the DB is added. |
| **speedtest-exporter** | Small container exposing internet speed (download / upload / ping) as a Prometheus-format endpoint. Netdata scrapes it every 6 hours, which triggers a fresh speed test on that schedule. |
| **Tailscale** | Secure remote access. Creates a private mesh network so the dashboard is reachable from a phone or laptop anywhere, without exposing any ports to the public internet. |

## Data Flow

1. Netdata reads host metrics via mounted `/proc`, `/sys`, `/etc/os-release`, and
   the Docker socket → renders them live in the dashboard.
2. Netdata scrapes the speedtest-exporter endpoint on a 6-hour interval → internet
   speed graphs appear alongside system metrics.
3. When a metric crosses a configured threshold (high CPU temperature, disk near
   full, RAM exhaustion, a container in a stopped/unhealthy state), Netdata's
   health engine sends a message via the **Telegram bot**.
4. The user views everything at `:19999` — on the local network, or remotely over
   Tailscale.

## Key Configuration Details

### Temperatures (Mac mini host prep)
Apple hardware running Ubuntu needs the `lm-sensors` package and the appropriate
kernel modules (`applesmc` for Apple SMC fan/temperature sensors, `coretemp` for
Intel CPU core temps) loaded on the **host**. Once sensors are exposed via
`lm-sensors`, Netdata picks them up automatically. This is the one mandatory
host-side preparation step before the stack is useful for temperature monitoring.

### Alerts → Telegram
1. Create a bot via [@BotFather](https://t.me/BotFather) to obtain a **bot token**.
2. Obtain the destination **chat ID** (e.g. by messaging the bot and reading
   `getUpdates`, documented step-by-step in the README).
3. Both values go into the git-ignored `.env` file and are wired into Netdata's
   health notification config (`health_alarm_notify.conf`).
4. Tune a small set of thresholds: CPU/sensor temperature, disk usage %, RAM
   usage, and Docker container down/unhealthy.

### Secrets handling
The Telegram bot token, chat ID, and Tailscale auth key live in a `.env` file that
is listed in `.gitignore` and never committed. A `.env.example` with placeholders
is committed so the required variables are documented.

## Deliverables

- `docker-compose.yml` — the three services (Netdata, speedtest-exporter, Tailscale)
  with correct host mounts and network settings.
- `.env.example` — placeholders for the Telegram bot token, chat ID, and Tailscale
  auth key.
- Netdata configuration:
  - Telegram notifications enabled and configured.
  - speedtest-exporter scrape job on a 6-hour interval.
  - Tuned alert thresholds (temperature, disk, RAM, container health).
- `README.md` — exact step-by-step setup commands, including the `lm-sensors` host
  prep and the Telegram bot/chat-ID retrieval, plus a verification checklist.
- `.gitignore` — ignores `.env` and any local runtime data.

## Scope Boundaries (YAGNI)

- **PostgreSQL monitoring:** the design reserves a clearly-marked, documented spot
  to enable Netdata's Postgres collector, but it will NOT be wired up until the
  database actually exists.
- **No Grafana / Prometheus:** Netdata covers the requirements. Adding Grafana is
  explicitly deferred unless a custom view is later needed that Netdata cannot
  provide.
- **No multi-server / Netdata Cloud:** single-host, free local agent only.

## Verification

The README includes a checklist to confirm success:
- Dashboard reachable at `http://<server-ip>:19999`.
- Temperature charts populated (sensors visible).
- Each running Docker container appears with live stats.
- Internet speed chart populates after the first scrape.
- A deliberately-triggered test alert arrives in Telegram.
- Dashboard reachable over Tailscale from a device off the home network.
