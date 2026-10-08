# La-Vie Enterprise Media Infrastructure Migration Guide
## Migrating from LiveKit Cloud to Self-Owned Dedicated Media Cluster (Hetzner)

---

### Executive Overview & Financial Impact

| Metric | LiveKit Cloud (Current) | Hetzner Dedicated Media Cluster (New) |
| :--- | :--- | :--- |
| **Pricing Model** | Base $50 + Metered Usage Overages | **Flat ~€27 to €58 / month total** |
| **Connection Minutes** | 150,000 min included ($0.0005/min overage) | **UNLIMITED ($0 per minute)** |
| **Monthly Bandwidth** | 250 GB included ($0.05/GB overage) | **20,000 GB (20 TB) included for free** |
| **Capacity** | 1,000 users | **1,000 to 2,000+ users per server** |
| **Monthly Cost at 10 Clients** | ~$5,300+ / month | **Flat ~€27 to €58 / month** |
| **Net Profit at 10 Clients ($3,500 rev)** | -$1,800 (Deficit) | **+$3,425 / month (97.8% profit margin)** |

---

### Prerequisites & Architecture Map

```
                  [ La-Vie Client Apps (Web & Flutter Mobile) ]
                                       │
                ┌──────────────────────┴──────────────────────┐
                ▼                                             ▼
     [ FastAPI Control Backend ]                    [ Dedicated LiveKit SFU Node ]
     • URL: la-vie.lifechangerstouch.org            • Domain: rtc.lifechangerstouch.org
     • Generates Tokens, Auth, DB                   • Hetzner Cloud (CPX41 / CCX33)
     • Connects via API Key/Secret                  • Handles all WebRTC Audio/Video
                                                    • 20 TB Free Bandwidth / 1 Gbps port
```

---

## Phase 1: Provision the Server on Hetzner Cloud

1. Log into the **Hetzner Cloud Console** at [console.hetzner.cloud](https://console.hetzner.cloud).
2. Create or select your project (e.g., `LaVie-Production`).
3. Click **Add Server** and configure the following options:

### Recommended Configuration
* **Location:** 
  * Choose **Germany (Nuremberg or Falkenstein)** or **Finland (Helsinki)** for global/African distribution.
  * Choose **USA (Ashburn)** if your primary audience is North America.
* **Image (OS):**
  * Select **Ubuntu 24.04 LTS** (Standard 64-bit Linux).
* **Type (Hardware Specs):**
  * **Option A: Best Value (Recommended to Start):**  
    * **Model:** **CPX41** (Shared AMD)
    * **Specs:** 8 AMD vCPUs, 16 GB RAM, 240 GB NVMe SSD, 1 Gbps port
    * **Bandwidth:** 20 TB (20,000 GB) included
    * **Cost:** **~€27.00 / month (~$29 / mo)**
    * **Capacity:** Up to 1,000 concurrent video participants.
  * **Option B: Dedicated Enterprise Power:**  
    * **Model:** **CCX33** (Dedicated AMD Cores)
    * **Specs:** 8 Dedicated vCPUs, 32 GB RAM, 240 GB NVMe SSD, 1 Gbps port
    * **Cost:** **~€58.00 / month (~$63 / mo)**
    * **Capacity:** 2,000+ concurrent video participants with guaranteed dedicated CPU cycles.
* **Networking:**
  * Ensure **Public IPv4** is enabled (provides your dedicated public IP).
* **SSH Keys:**
  * Upload your public SSH key (or select password login sent to your email).
* **Name:**
  * Name the instance: `lavie-rtc-server`.
4. Click **Create & Buy Now**. The instance will be online in under 30 seconds.
5. Copy your new server's **Public IPv4 Address** (e.g., `159.69.123.45`).

---

## Phase 2: DNS & Domain Configuration

Configure the dedicated subdomain for WebRTC video routing.

1. Open your DNS management console for `lifechangerstouch.org` (cPanel, Cloudflare, Namecheap, Route53, etc.).
2. Add an **A Record**:
   * **Record Type:** `A`
   * **Host / Name:** `rtc`
   * **Target / Points to:** `[Your Hetzner Public IPv4 Address]`
   * **TTL:** `300` (or Automatic)
   * **Proxy Status:** If using Cloudflare, set to **DNS Only (Gray Cloud)** because WebRTC UDP traffic must connect directly to the server.
3. Verify DNS propagation in your terminal:
   ```bash
   ping rtc.lifechangerstouch.org
   ```
   *(Ensure it responds with your Hetzner server's IP address).*

---

## Phase 3: Hetzner Cloud Firewall Configuration

In the Hetzner Cloud Console, create and attach a Firewall to your server with the following rules:

### Inbound Rules:
| Protocol | Port / Range | Description |
| :--- | :--- | :--- |
| **TCP** | `22` | SSH Server Administration |
| **TCP** | `80` | HTTP (Let's Encrypt SSL Verification) |
| **TCP** | `443` | HTTPS / WSS WebRTC Signaling |
| **TCP** | `7880` | LiveKit HTTP/WebSocket API |
| **TCP** | `7881` | LiveKit WebRTC TCP Fallback |
| **UDP** | `7882` | LiveKit WebRTC UDP Signaling |
| **UDP** | `50000 - 60000` | WebRTC Media ICE Transport (Video & Audio Streams) |

---

## Phase 4: Deploy LiveKit Server with Automated SSL

Connect to your Hetzner server via SSH:
```bash
ssh root@your-hetzner-ip
```

### 1. Update Ubuntu & Install Base Tools
```bash
apt update && apt upgrade -y
apt install curl git ufw -y
```

### 2. Install LiveKit Server
Run the official LiveKit installer script:
```bash
curl -sSL https://get.livekit.io | bash
```

### 3. Generate Keys & Configuration
Generate your unique production API Key and Secret:
```bash
livekit-server generate-keys
```
*(Copy the generated `API Key` and `API Secret` securely).*

### 4. Automated Production Setup (With Let's Encrypt SSL)
LiveKit includes an automated setup wizard that installs Docker, configures Caddy for automatic Let's Encrypt SSL certificates, and sets up system services:
```bash
livekit-server setup
```
When prompted:
* **Primary Domain Name:** Enter `rtc.lifechangerstouch.org`
* **Turn server domain:** Enter `rtc.lifechangerstouch.org`
* Provide your generated API Key and Secret.

Alternatively, if running via Docker Compose manually:
Create `/opt/livekit/docker-compose.yaml`:
```yaml
version: '3.9'

services:
  caddy:
    image: livekit/caddyl4
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./caddy.yaml:/etc/caddy.yaml
      - ./caddy_data:/data

  livekit:
    image: livekit/livekit-server:latest
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./livekit.yaml:/etc/livekit.yaml
    command: --config /etc/livekit.yaml
```

Create `/opt/livekit/livekit.yaml`:
```yaml
port: 7880
bind_addresses:
  - ""

rtc:
  tcp_port: 7881
  port_range_start: 50000
  port_range_end: 60000
  use_external_ip: true

keys:
  YOUR_NEW_API_KEY: YOUR_NEW_API_SECRET

logging:
  json: false
  level: info
```

Start the service:
```bash
cd /opt/livekit && docker compose up -d
```

### 5. Verify the Server Health
From your local computer or browser, run:
```bash
curl https://rtc.lifechangerstouch.org
```
It should return:
```
OK
```

---

## Phase 5: Update La-Vie Backend Configuration

No code changes are needed in your Python backend or mobile clients. You only update [.env](file:///c:/xampp/htdocs/conferenceMe/.env):

```env
# =====================================================================
# LIVEKIT ENTERPRISE CLUSTER CONFIGURATION (SELF-HOSTED HETZNER)
# =====================================================================
LIVEKIT_API_KEY=your_new_api_key_from_phase_4
LIVEKIT_API_SECRET=your_new_api_secret_from_phase_4

# LiveKit HTTP API URL (Used by backend to kick/mute users & mint tokens)
LIVEKIT_URL=https://rtc.lifechangerstouch.org

# LiveKit WebSocket URL (Used by frontend web and mobile apps for video)
LIVEKIT_WSS_URL=wss://rtc.lifechangerstouch.org
```

Restart your FastAPI application server:
```bash
# On your application server:
sudo systemctl restart lavie.service
# Or if running via uvicorn directly:
python -m uvicorn main:app --host 0.0.0.0 --port 80
```

---

## Phase 6: Why Zero Client App Rebuilds Are Needed

Your web application and Flutter mobile app are engineered to dynamically fetch credentials from the backend:
1. When a user joins a meeting, the client requests a token from `/token/{room_name}/{peer_id}` or `/api/call/token`.
2. The FastAPI backend mints the JWT using the new keys and returns `{"token": token, "url": LIVEKIT_WSS_URL}` ([main.py:L3500-L3513](file:///c:/xampp/htdocs/conferenceMe/main.py#L3500-L3513)).
3. The client connects directly to `wss://rtc.lifechangerstouch.org`.

**Result:** Users already using your Flutter APK or web link will instantly migrate to the new dedicated server without reinstalling the app or updating anything!

---

## Phase 7: Scaling to 50+ Enterprise Clients (Decade-Proof Clustering)

When your user base grows beyond 2,000 simultaneous active video callers, you scale horizontally using LiveKit's native Redis clustering:

1. Install Redis on your server (or a separate Redis node):
   ```bash
   apt install redis-server -y
   ```
2. In `livekit.yaml`, enable Redis:
   ```yaml
   redis:
     address: 127.0.0.1:6379
     password: your_secure_redis_password
   ```
3. When adding a 2nd or 3rd server node in another datacenter (e.g., US, UK, South Africa):
   * Deploy LiveKit server on the new node.
   * Point its `redis.address` to your primary Redis instance.
   * LiveKit will automatically discover all nodes and balance meeting rooms across the global cluster seamlessly.

---

### Migration Checklist & Verification

- [ ] Hetzner Cloud CPX41 or CCX33 server created with Ubuntu 24.04.
- [ ] DNS `rtc.lifechangerstouch.org` pointed to Hetzner IPv4 address (DNS Only).
- [ ] Firewall rules configured (TCP 80, 443, 7880, 7881; UDP 50000–60000).
- [ ] LiveKit server installed and SSL certificate active via Let's Encrypt.
- [ ] `curl https://rtc.lifechangerstouch.org` returns `OK`.
- [ ] [.env](file:///c:/xampp/htdocs/conferenceMe/.env) updated with new Keys and `rtc.lifechangerstouch.org` URLs.
- [ ] Test call initiated on `https://la-vie.lifechangerstouch.org` to confirm crystal-clear HD video and audio forwarding.
- [ ] 300+ participant meeting verified with stable latency and 20 TB monthly bandwidth headroom.
