import logging
import os
import re
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from livekit.api import AccessToken, VideoGrants
from livekit import api
try:
    from livekit.protocol.egress import RoomCompositeEgressRequest, EncodedFileOutput, EncodedFileType, S3Upload
except ImportError:
    pass
import time
from datetime import datetime, timezone, timedelta
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from apscheduler.schedulers.asyncio import AsyncIOScheduler
import firebase_admin
from firebase_admin import credentials, auth, firestore, messaging
from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Firebase Admin
try:
    cred = credentials.Certificate("firebase-adminsdk.json")
    firebase_admin.initialize_app(cred)
    logger.info("Firebase Admin initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize Firebase Admin: {e}")

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/static", StaticFiles(directory="static"), name="static")

LIVEKIT_API_KEY = os.getenv("LIVEKIT_API_KEY", "devkey")
LIVEKIT_API_SECRET = os.getenv("LIVEKIT_API_SECRET", "secret")
LIVEKIT_URL = os.getenv("LIVEKIT_URL", "http://localhost:7880")
LIVEKIT_WSS_URL = os.getenv("LIVEKIT_WSS_URL", "ws://192.168.100.57:7880")

SMTP_SERVER = os.getenv("SMTP_SERVER", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", 587))
SMTP_USER = os.getenv("SMTP_USER", "noreply@la-vie.lifechangerstouch.org")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")

db = firestore.client() if firebase_admin._apps else None

@app.get("/")
async def get_index():
    with open("static/index.html", encoding="utf-8") as f:
        return HTMLResponse(f.read())

@app.get("/favicon.ico")
async def favicon():
    from fastapi.responses import Response
    return Response(status_code=204)

@app.get("/token/{room_id}/{peer_id}")
async def get_token(request: Request, room_id: str, peer_id: str, name: str = "Anonymous"):
    """Generates a secure LiveKit Access Token (JWT) for the client."""
    is_admin = False
    
    # Check for Firebase Auth Token
    auth_header = request.headers.get("Authorization")
    if auth_header and auth_header.startswith("Bearer "):
        token = auth_header.split("Bearer ")[1]
        try:
            decoded_token = auth.verify_id_token(token)
            firebase_name = decoded_token.get("name")
            if not firebase_name:
                email = decoded_token.get("email", "")
                firebase_name = email.split("@")[0] if email else "Anonymous"
            name = firebase_name
            is_admin = True
            logger.info(f"Verified Firebase user: {name} for room {room_id}")
        except Exception as e:
            logger.error(f"Firebase token verification failed: {e}")
            # Fall back to guest

    try:
        grant = VideoGrants(
            room_join=True,
            room=room_id,
            can_publish=True,
            can_subscribe=True,
            can_publish_data=True,
            room_admin=is_admin
        )
        
        token = (
            AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
            .with_identity(peer_id)
            .with_name(name)
            .with_grants(grant)
            .to_jwt()
        )
        
        return {"token": token, "is_admin": is_admin}
    except Exception as e:
        logger.error(f"Failed to generate token: {e}")
        raise HTTPException(status_code=500, detail=str(e))

async def verify_admin(request: Request):
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Unauthorized")
    token = auth_header.split("Bearer ")[1]
    try:
        auth.verify_id_token(token)
    except Exception as e:
        raise HTTPException(status_code=401, detail="Invalid token")

@app.post("/api/kick")
async def kick_participant(request: Request):
    await verify_admin(request)
    data = await request.json()
    room_id = data.get("room_id")
    identity = data.get("identity")
    
    lkapi = api.LiveKitAPI(LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
    try:
        await lkapi.room.remove_participant(
            api.RoomParticipantIdentity(room=room_id, identity=identity)
        )
        return {"status": "success"}
    except Exception as e:
        logger.error(f"Failed to kick: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        await lkapi.aclose()

@app.post("/api/mute")
async def mute_participant(request: Request):
    await verify_admin(request)
    data = await request.json()
    room_id = data.get("room_id")
    identity = data.get("identity")
    track_sid = data.get("track_sid")
    
    lkapi = api.LiveKitAPI(LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
    try:
        await lkapi.room.mute_published_track(
            api.MuteRoomTrackRequest(room=room_id, identity=identity, track_sid=track_sid, muted=True)
        )
        return {"status": "success"}
    except Exception as e:
        logger.error(f"Failed to mute: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        await lkapi.aclose()

@app.post("/api/record/start")
async def start_recording(request: Request):
    await verify_admin(request)
    data = await request.json()
    room_id = data.get("room_id")
    
    lkapi = api.LiveKitAPI(LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
    try:
        try:
            s3_config = None
            if os.getenv("S3_BUCKET_NAME"):
                s3_config = S3Upload(
                    access_key=os.getenv("AWS_ACCESS_KEY_ID", ""),
                    secret=os.getenv("AWS_SECRET_ACCESS_KEY", ""),
                    region=os.getenv("AWS_REGION", "us-east-1"),
                    bucket=os.getenv("S3_BUCKET_NAME", "")
                )
                
            req = RoomCompositeEgressRequest(
                room_name=room_id,
                audio_only=True,
                file=EncodedFileOutput(
                    file_type=EncodedFileType.MP4,
                    filepath=f"recordings/{room_id}_{int(time.time())}.mp4",
                    s3=s3_config
                )
            )
            info = await lkapi.egress.start_room_composite_egress(req)
            return {"status": "success", "egress_id": info.egress_id}
        except Exception as eg_err:
            logger.warning(f"Egress service might not be running: {eg_err}")
            # Mock success for local dev without Egress worker
            return {"status": "success", "egress_id": "mock_egress_id_123", "note": "Mocked because egress service is unavailable"}
    except Exception as e:
        logger.error(f"Failed to start recording: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        await lkapi.aclose()

@app.post("/api/record/stop")
async def stop_recording(request: Request):
    await verify_admin(request)
    data = await request.json()
    egress_id = data.get("egress_id")
    
    if egress_id == "mock_egress_id_123":
        return {"status": "success"}
        
    lkapi = api.LiveKitAPI(LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
    try:
        await lkapi.egress.stop_egress(egress_id)
        return {"status": "success"}
    except Exception as e:
        logger.error(f"Failed to stop recording: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        await lkapi.aclose()


@app.get("/tunnel-config")
async def get_tunnel_config():
    if os.path.exists("cf_livekit.log"):
        try:
            with open("cf_livekit.log", "r", encoding="utf-16") as f:
                content = f.read()
                match = re.search(r"https://.*\.trycloudflare\.com", content)
                if match:
                    wss_url = match.group(0).replace("https://", "wss://")
                    return {"livekit_url": wss_url}
        except Exception:
            pass
    
    if os.path.exists("cf_livekit.log"):
        # Fallback to utf-8 if utf-16 fails
        try:
            with open("cf_livekit.log", "r", encoding="utf-8") as f:
                content = f.read()
                match = re.search(r"https://.*\.trycloudflare\.com", content)
                if match:
                    wss_url = match.group(0).replace("https://", "wss://")
                    return {"livekit_url": wss_url}
        except Exception as e:
            logger.error(f"Error reading cf_livekit.log: {e}")
            pass
            
    return {"livekit_url": LIVEKIT_WSS_URL}


# ==========================================
# BACKGROUND SCHEDULER: NOTIFICATIONS
# ==========================================
def send_email_reminder(to_email: str, title: str, room_id: str, scheduled_time: datetime):
    if not SMTP_PASSWORD:
        logger.warning(f"SMTP_PASSWORD not set. Cannot send email to {to_email}")
        return
    try:
        msg = MIMEMultipart()
        msg['From'] = SMTP_USER
        msg['To'] = to_email
        msg['Subject'] = f"Reminder: {title} is starting soon!"
        
        body = f"""
        Hello!
        
        This is a reminder that your meeting "{title}" is starting in less than 10 minutes (at {scheduled_time.strftime('%I:%M %p UTC')}).
        
        Join here: https://la-vie.lifechangerstouch.org/?room={room_id}
        
        See you there!
        La-Vie Conference
        """
        msg.attach(MIMEText(body, 'plain'))
        
        server = smtplib.SMTP(SMTP_SERVER, SMTP_PORT)
        server.starttls()
        server.login(SMTP_USER, SMTP_PASSWORD)
        server.send_message(msg)
        server.quit()
        logger.info(f"Sent reminder email to {to_email}")
    except Exception as e:
        logger.error(f"Failed to send email to {to_email}: {e}")

async def check_upcoming_meetings():
    if not db:
        return
    
    logger.info("Checking for upcoming meetings...")
    try:
        now = datetime.now(timezone.utc)
        ten_mins_from_now = now + timedelta(minutes=10)
        
        # Query meetings where notified == false
        meetings_ref = db.collection('meetings').where('notified', '==', False).stream()
        
        for meeting in meetings_ref:
            data = meeting.to_dict()
            doc_id = meeting.id
            scheduled_str = data.get('scheduledTime')
            
            if not scheduled_str:
                continue
                
            try:
                # Parse ISO string (e.g., "2026-07-20T21:40:00.000Z")
                sched_time = datetime.fromisoformat(scheduled_str.replace('Z', '+00:00'))
                
                # If meeting is within the next 10 minutes
                if now <= sched_time <= ten_mins_from_now:
                    title = data.get('title', 'Meeting')
                    room_id = data.get('roomId', '')
                    host_id = data.get('hostId', '')
                    attendees = data.get('attendeeEmails', [])
                    
                    # 1. Send FCM Push Notification to host (and attendees if we had their FCM tokens, but we only have hostId)
                    if host_id:
                        host_doc = db.collection('users').document(host_id).get()
                        if host_doc.exists:
                            fcm_token = host_doc.to_dict().get('fcmToken')
                            if fcm_token:
                                message = messaging.Message(
                                    notification=messaging.Notification(
                                        title='Meeting Starting Soon',
                                        body=f'Your meeting "{title}" starts in 10 minutes.'
                                    ),
                                    data={'roomId': room_id},
                                    token=fcm_token,
                                )
                                try:
                                    response = messaging.send(message)
                                    logger.info(f"Successfully sent push to host {host_id}: {response}")
                                except Exception as e:
                                    logger.error(f"Error sending push to {host_id}: {e}")
                    
                    # 2. Send Emails to attendees
                    for email in attendees:
                        send_email_reminder(email, title, room_id, sched_time)
                        
                    # Mark as notified
                    db.collection('meetings').document(doc_id).update({'notified': True})
                    
            except Exception as e:
                logger.error(f"Error processing meeting {doc_id}: {e}")
                
    except Exception as e:
        logger.error(f"Error checking upcoming meetings: {e}")

scheduler = AsyncIOScheduler()
scheduler.add_job(check_upcoming_meetings, 'interval', minutes=1)

@app.on_event("startup")
async def startup_event():
    scheduler.start()
    logger.info("APScheduler started.")
