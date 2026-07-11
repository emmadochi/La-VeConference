# AWS & LiveKit Cloud Deployment Guide

This guide outlines the exact steps to take your La-Vie Conference app from your local computer and put it online for the world to use, completely for free (within the generous free tier limits).

We are using a **Hybrid Architecture**:
1. **AWS Free Tier**: Hosts your Frontend (HTML/JS) and Backend (Python FastAPI).
2. **LiveKit Cloud**: Handles the heavy WebRTC video streaming.

---

## Phase 1: Set up LiveKit Cloud (Video Server)
*Since video streaming is too heavy for a free AWS server, we offload it here.*

1. **Create an Account**: Go to [cloud.livekit.io](https://cloud.livekit.io/) and sign up for a free account.
2. **Create a Project**: Once logged in, click "New Project". Give it a name (e.g., `LaVie-Prod`).
3. **Get Your API Keys**: 
   - Go to your Project Settings -> **Keys**.
   - Generate a new API Key and Secret. Keep this tab open, you will need these in Phase 3!
4. **Get Your WebSocket URL**: 
   - On your project dashboard, find your **WSS URL** (it will look something like `wss://lavie-prod-1234.livekit.cloud`).

---

## Phase 2: Prepare AWS (Hosting)
*You will need a credit card to verify your identity on AWS, but you will not be charged if you stay within the free tier.*

1. **Create an AWS Account**: Go to [aws.amazon.com/free](https://aws.amazon.com/free) and sign up.
2. **Launch an EC2 Server**:
   - Go to the **EC2 Dashboard** and click **Launch Instance**.
   - **Name**: `LaVie-Server`
   - **OS**: Ubuntu 22.04 LTS (or Amazon Linux 2023).
   - **Instance Type**: Select **t2.micro** (this is the "Free tier eligible" one).
   - **Key Pair**: Create a new Key Pair (download the `.pem` file to your computer; you'll need it to SSH into the server).
   - **Network Settings**: Check the boxes to **Allow HTTP traffic from the internet** and **Allow HTTPS traffic**.
   - Click **Launch**.

---

## Phase 3: Deploy the Backend (Python) to AWS
*Now we move your Python code to the cloud server.*

1. **Connect to your EC2 Server**: 
   - Use SSH or the "EC2 Instance Connect" button in your AWS dashboard to open a terminal to your server.
2. **Install Python & Dependencies**:
   Run these commands on your AWS server:
   ```bash
   sudo apt update
   sudo apt install python3-pip python3-venv git -y
   ```
3. **Upload Your Code**:
   - You can push your `main.py` and `firebase-adminsdk.json` to GitHub, and then `git clone` it onto your server.
   - *Alternatively*, you can securely copy (SCP) the files from your Windows machine to the AWS server.
4. **Update `main.py` with LiveKit Cloud Keys**:
   Open `main.py` on the server and change the local keys to your new LiveKit Cloud keys from Phase 1:
   ```python
   LIVEKIT_API_KEY = "your_livekit_cloud_key_here"
   LIVEKIT_API_SECRET = "your_livekit_cloud_secret_here"
   ```
   *(Also ensure the `/tunnel-config` endpoint or frontend points to your new LiveKit Cloud WSS URL instead of localhost).*
5. **Start the Server**:
   ```bash
   pip install fastapi uvicorn livekit firebase-admin
   python3 -m uvicorn main:app --host 0.0.0.0 --port 80
   ```
   *(Note: To keep it running when you close the terminal, you will eventually want to use a tool like `tmux`, `screen`, or a system service like `systemd`).*

---

## Phase 4: Deploy the Frontend
Because your Python server (FastAPI) is already serving your `index.html` file out of the `static` folder, your frontend is technically already deployed!

1. Go to your AWS EC2 Dashboard.
2. Find the **Public IPv4 Address** of your `LaVie-Server`.
3. Type that IP address into your browser (e.g., `http://54.123.45.67`).
4. You should see your La-Vie Conference app!

---

## Phase 5: Get a Domain Name & HTTPS (Required for Video)
*Browsers **block** camera and microphone access on `http://` sites. You MUST have a secure `https://` domain for a video calling app to work.*

1. **Get a Domain Name**: Buy a cheap domain name on Namecheap, GoDaddy, or AWS Route53 (e.g., `lavie-conference.com`).
2. **Point Domain to AWS**: In your domain registrar's DNS settings, create an "A Record" that points to your AWS EC2 Public IP address.
3. **Install SSL (HTTPS)**: 
   On your AWS EC2 server, install **Certbot** to get a free SSL certificate from Let's Encrypt:
   ```bash
   sudo apt install certbot
   sudo certbot certonly --standalone -d your-domain.com
   ```
4. **Update FastAPI for HTTPS**:
   Run Uvicorn with your new SSL certificates:
   ```bash
   python3 -m uvicorn main:app --host 0.0.0.0 --port 443 --ssl-keyfile=/etc/letsencrypt/live/your-domain.com/privkey.pem --ssl-certfile=/etc/letsencrypt/live/your-domain.com/fullchain.pem
   ```

### You're Live! 🎉
Users can now go to `https://your-domain.com`. The website is served by your free AWS server, and when they join a call, the heavy video lifting is flawlessly handled by your free LiveKit Cloud project!
