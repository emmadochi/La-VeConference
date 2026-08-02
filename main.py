import logging
import os
import re
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from livekit.api import AccessToken, VideoGrants, WebhookReceiver
from livekit import api
try:
    from livekit.api import IngressClient
    from livekit.protocol.ingress import CreateIngressRequest, IngressInput
except ImportError:
    try:
        from livekit.api import IngressClient, CreateIngressRequest, IngressInput
    except ImportError:
        IngressClient = None
        CreateIngressRequest = None
        IngressInput = None

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

@app.get("/admin")
async def get_admin():
    with open("static/admin.html", encoding="utf-8") as f:
        return HTMLResponse(f.read())

@app.get("/api/admin/stats")
async def get_admin_stats(request: Request):
    await verify_admin(request)
    
    if not db:
        raise HTTPException(status_code=500, detail="Database not initialized")
        
    try:
        # Get users
        users_ref = db.collection("users")
        all_users = users_ref.get()
        total_users = len(all_users)
        
        users_data = []
        active_rooms = 0
        for doc in all_users:
            user_dict = doc.to_dict()
            if user_dict.get("active_room"):
                active_rooms += 1
            users_data.append({
                "id": doc.id,
                "email": user_dict.get("email", "Unknown"),
                "displayName": user_dict.get("displayName", ""),
                "active_room": user_dict.get("active_room", "")
            })
        
        # Get meetings
        meetings_ref = db.collection("meetings")
        all_meetings = meetings_ref.get()
        total_meetings = len(all_meetings)
        
        meetings_data = []
        for doc in all_meetings:
            meet_dict = doc.to_dict()
            meetings_data.append({
                "id": doc.id,
                "title": meet_dict.get("title", "Untitled"),
                "scheduled_time": meet_dict.get("scheduled_time"),
                "host_id": meet_dict.get("host_id", "")
            })
        
        # Sort by most recent/upcoming (assuming ISO strings for scheduled_time)
        meetings_data = sorted(meetings_data, key=lambda x: x["scheduled_time"] or "", reverse=True)
        
        return {
            "total_users": total_users,
            "active_rooms": active_rooms,
            "total_meetings": total_meetings,
            "users": users_data,
            "meetings": meetings_data
        }
    except Exception as e:
        logger.error(f"Error fetching admin stats: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch stats")

@app.get("/favicon.ico")
async def favicon():
    from fastapi.responses import Response
    return Response(status_code=204)

@app.get("/.well-known/assetlinks.json")
async def assetlinks():
    from fastapi.responses import FileResponse
    return FileResponse("static/.well-known/assetlinks.json", media_type="application/json")

@app.post("/api/lichat/token")
async def generate_lichat_token(request: Request):
    """Generates a secure LiveKit Access Token for the LiChat app."""
    try:
        data = await request.json()
        room_name = data.get("roomName")
        participant_name = data.get("participantName")
        
        if not room_name or not participant_name:
            raise HTTPException(status_code=400, detail="roomName and participantName are required")
            
        token = AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
        token.with_identity(participant_name)
        token.with_name(participant_name)
        token.with_grants(VideoGrants(room_join=True, room=room_name))
        
        return {"token": token.to_jwt()}
    except Exception as e:
        logger.error(f"Error generating LiChat token: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

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
            uid = decoded_token.get("uid")
            firebase_name = decoded_token.get("name")
            if not firebase_name:
                email = decoded_token.get("email", "")
                firebase_name = email.split("@")[0] if email else "Anonymous"
            name = firebase_name
            is_admin = True
            logger.info(f"Verified Firebase user: {name} for room {room_id}")

            # Check for active meetings across the account
            if uid:
                db = firestore.client()
                user_ref = db.collection("users").document(uid)
                user_doc = user_ref.get()
                
                if user_doc.exists:
                    data = user_doc.to_dict()
                    active_room = data.get("active_room")
                    if active_room and active_room != room_id:
                        logger.warning(f"User {uid} attempted to join {room_id} but is already active in {active_room}")
                        from fastapi import HTTPException
                        raise HTTPException(status_code=403, detail="You are already in another meeting.")
                
                # Update their active room
                user_ref.set({"active_room": room_id}, merge=True)

        except HTTPException:
            raise
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
        decoded_token = auth.verify_id_token(token)
        email = decoded_token.get("email", "")
        uid = decoded_token.get("uid")
        
        if email == "la-vie@adminnew.com":
            return True
            
        if uid and db:
            user_doc = db.collection("users").document(uid).get()
            if user_doc.exists and user_doc.to_dict().get("isAdmin") == True:
                return True
                
        raise HTTPException(status_code=403, detail="Forbidden: Admin access required")
    except HTTPException:
        raise
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


@app.post("/api/end_meeting")
async def end_meeting(request: Request):
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Unauthorized")
    
    token = auth_header.split("Bearer ")[1]
    try:
        decoded_token = auth.verify_id_token(token)
        uid = decoded_token.get("uid")
        email = decoded_token.get("email", "")
    except Exception as e:
        logger.error(f"End meeting token verification failed: {e}")
        raise HTTPException(status_code=401, detail="Invalid token")

    data = await request.json()
    room_id = data.get("room_id")
    if not room_id:
        raise HTTPException(status_code=400, detail="room_id is required")

    logger.info(f"End meeting request for room {room_id} by user {uid} ({email})")

    lkapi = api.LiveKitAPI(LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
    try:
        # Delete room on LiveKit server - this terminates WebRTC and disconnects ALL participants!
        await lkapi.room.delete_room(api.DeleteRoomRequest(room=room_id))
        logger.info(f"Successfully deleted LiveKit room {room_id}")

        # Clear active_room for all users currently marked in this room in Firestore
        if db:
            try:
                users_in_room = db.collection("users").where("active_room", "==", room_id).get()
                for udoc in users_in_room:
                    udoc.reference.set({"active_room": ""}, merge=True)
                logger.info(f"Cleared active_room in Firestore for users in room {room_id}")
            except Exception as fe:
                logger.warning(f"Failed to clear active_room in Firestore: {fe}")

        return {"status": "success"}
    except Exception as e:
        logger.error(f"Failed to end meeting {room_id}: {e}")
        if db and uid:
            try:
                db.collection("users").document(uid).set({"active_room": ""}, merge=True)
            except Exception:
                pass
        return {"status": "success", "warning": str(e)}
    finally:
        await lkapi.aclose()


@app.post("/api/create_ingress")
async def create_ingress(request: Request):
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Unauthorized")
    
    token = auth_header.split("Bearer ")[1]
    try:
        decoded_token = auth.verify_id_token(token)
        uid = decoded_token.get("uid")
    except Exception as e:
        logger.error(f"Ingress token verification failed: {e}")
        raise HTTPException(status_code=401, detail="Invalid token")

    data = await request.json()
    room_id = data.get("room_id")
    if not room_id:
        raise HTTPException(status_code=400, detail="room_id is required")

    logger.info(f"Generating vMix RTMP Ingress credentials for room {room_id} by user {uid}")

    if IngressClient and CreateIngressRequest and IngressInput:
        try:
            ingress_client = IngressClient(LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
            req = CreateIngressRequest(
                input_type=IngressInput.RTMP_INPUT,
                name="vMix Live Stage",
                room_name=room_id,
                participant_identity="vmix_stage_feed",
                participant_name="Main Stage 🎥"
            )
            ingress_info = await ingress_client.create_ingress(req)
            await ingress_client.aclose()

            rtmp_url = getattr(ingress_info, 'url', None) or f"rtmp://{request.url.hostname}/live"
            stream_key = getattr(ingress_info, 'stream_key', None) or f"key_{room_id}"

            return {
                "status": "success",
                "rtmp_url": rtmp_url,
                "stream_key": stream_key
            }
        except Exception as e:
            logger.warn(f"LiveKit Ingress API call notice: {e}")

    # Fallback RTMP credentials format for host vMix setup
    host = request.url.hostname or "la-vie.lifechangerstouch.org"
    return {
        "status": "success",
        "rtmp_url": f"rtmp://{host}/live",
        "stream_key": f"lavie-stage-{room_id}",
        "info": "RTMP connection credentials for vMix / OBS stream ingest"
    }


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

@app.post("/webhook")
async def livekit_webhook(request: Request):
    body = await request.body()
    auth_token = request.headers.get("Authorization", "")
    receiver = WebhookReceiver(LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
    try:
        event = receiver.receive(body.decode('utf-8'), auth_token)
        if event.event == "participant_left":
            uid = event.participant.identity
            # Check if this UID is a Firebase user
            if uid:
                db = firestore.client()
                user_ref = db.collection("users").document(uid)
                user_doc = user_ref.get()
                if user_doc.exists:
                    data = user_doc.to_dict()
                    # Only clear if the active room matches the room they left, to prevent race conditions
                    if data.get("active_room") == event.room.name:
                        user_ref.set({"active_room": ""}, merge=True)
                        logger.info(f"Cleared active_room for user {uid} via webhook")
        return {"status": "ok"}
    except Exception as e:
        logger.error(f"Webhook error: {e}")
        return {"status": "error"}
