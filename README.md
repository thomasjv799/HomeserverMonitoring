# Home Server Monitoring

A one-command Docker stack that gives this Ubuntu home server (an old Mac mini) a
live dashboard for system health, temperatures, Docker containers, and internet
speed — with Telegram alerts and secure remote access via Tailscale.

Dashboard: **http://<server-ip>:19999** (or over Tailscale from anywhere).

## What runs

- **Netdata** — the dashboard + alert engine (CPU, RAM, disk, network, temps, Docker).
- **speedtest-exporter** — internet speed, scraped by Netdata every 6 hours.
- **Tailscale** — installed on the host (not a container) for secure remote access.

---

## 1. Host prerequisites

### Docker + Compose
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"   # log out/in afterwards so docker runs without sudo
```

### Temperature sensors (required for temps to show up)
```bash
sudo apt update
sudo apt install -y lm-sensors
sudo sensors-detect --auto
# Apple hardware exposes temps/fans via these modules:
sudo modprobe applesmc || true
sudo modprobe coretemp || true
sensors    # confirm you see temperatures here before continuing
```
If `sensors` prints temperatures, Netdata will pick them up automatically.

---

## 2. Create the Telegram bot

1. In Telegram, message **@BotFather**, send `/newbot`, follow the prompts.
2. Copy the **bot token** it gives you (looks like `123456789:AA...`).

### Get your chat ID
1. Send any message to your new bot.
2. Run (replace `<TOKEN>`):
   ```bash
   curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" | grep -oP '"chat":\{"id":\K-?[0-9]+'
   ```
   The number printed is your **chat ID** (group chats have a leading `-`).

---

## 3. Configure secrets

```bash
cp .env.example .env
```
Edit `.env` and set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` to the values above.
`.env` is git-ignored and never committed.

---

## 4. Bring up the stack

```bash
docker compose up -d
docker compose ps      # both containers should be "running"/"healthy"
```

Open **http://<server-ip>:19999**.

> Note: the `./netdata` directory is mounted as the container's config dir. On
> first run Netdata copies its stock config into the empty slots, so our three
> files just override the relevant bits. Do **not** add a bare `netdata.conf` to
> `./netdata` before first run — that can stop Netdata from seeding its defaults.

---

## 5. Remote access with Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```
Follow the printed login URL. Afterwards, reach the dashboard from any device on
your tailnet at **http://<tailscale-ip>:19999** — no public ports opened.

---

## 6. Verification checklist

- [ ] Dashboard loads at `http://<server-ip>:19999`.
- [ ] **Temperatures** appear (search the dashboard for "sensors"/"temperature").
- [ ] Each running **Docker container** shows up with live CPU/RAM/IO stats.
- [ ] After the first 6-hour scrape (or force one — see below), an **internet
      speed** chart appears under the Prometheus/speedtest section.
- [ ] A **test alert reaches Telegram** (run as the `netdata` user so it loads the config):
      ```bash
      docker exec -it netdata su -s /bin/bash netdata -c '/usr/libexec/netdata/plugins.d/alarm-notify.sh test'
      ```
      You should receive a test message in your Telegram chat.
- [ ] Dashboard reachable over **Tailscale** from a device off your home network.

### Force an immediate speed test (optional)
```bash
curl -s http://localhost:9798/metrics | grep speedtest_
```
This triggers a test now and prints the raw metrics.

---

## Future: monitor PostgreSQL

When you add a self-hosted PostgreSQL container, enable Netdata's Postgres
collector by creating `netdata/go.d/postgres.conf`:

```yaml
jobs:
  - name: local
    dsn: 'postgres://<user>:<password>@127.0.0.1:5432/postgres?sslmode=disable'
```
Put the credentials in `.env` and reference them, or use a read-only monitoring
role. Then `docker compose restart netdata`. Postgres charts will appear
automatically. (Not enabled yet — no database exists.)

---

## Updating

```bash
docker compose pull && docker compose up -d
```
