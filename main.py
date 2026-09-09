import logging
import os
import re
import random
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from livekit.api import AccessToken, VideoGrants, WebhookReceiver
from livekit import api
try:
    from livekit.api import IngressClient
    from livekit.protocol.ingress import CreateIngressRequest, IngressInput, ListIngressRequest
except ImportError:
    try:
        from livekit.api import IngressClient, CreateIngressRequest, IngressInput, ListIngressRequest
    except ImportError:
        IngressClient = None
        CreateIngressRequest = None
        IngressInput = None
        ListIngressRequest = None

try:
    from livekit.protocol.egress import (
        RoomCompositeEgressRequest, 
        EncodedFileOutput, 
        EncodedFileType, 
        S3Upload,
        StreamOutput,
        StreamProtocol
    )
except ImportError:
    StreamOutput = None
    StreamProtocol = None
    RoomCompositeEgressRequest = None
import time
from datetime import datetime, timezone, timedelta
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from apscheduler.schedulers.asyncio import AsyncIOScheduler
import firebase_admin
from firebase_admin import credentials, auth, firestore, messaging
from dotenv import load_dotenv
import email_templates

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

# Security HTTP Headers Middleware
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "SAMEORIGIN"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    if request.url.scheme == "https":
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response

# Rate Limiting Middleware for API & Token endpoints
RATE_LIMIT_STORE = {}
MAX_REQUESTS_PER_MINUTE = 60

@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    path = request.url.path
    if path.startswith("/api/") or path.startswith("/token/"):
        client_ip = request.client.host if request.client else "unknown"
        now = time.time()
        user_requests = [t for t in RATE_LIMIT_STORE.get(client_ip, []) if now - t < 60]
        if len(user_requests) >= MAX_REQUESTS_PER_MINUTE:
            logger.warning(f"Rate limit exceeded for IP: {client_ip} on path {path}")
            return Response(
                content='{"detail":"Rate limit exceeded. Please try again in a minute."}',
                status_code=429,
                media_type="application/json"
            )
        user_requests.append(now)
        RATE_LIMIT_STORE[client_ip] = user_requests

    return await call_next(request)

allowed_origins_env = os.getenv("ALLOWED_ORIGINS", "")
allowed_origins = [o.strip() for o in allowed_origins_env.split(",") if o.strip()]
default_origins = ["https://la-vie.lifechangerstouch.org", "http://localhost:8000", "http://localhost:3000", "http://127.0.0.1:8000"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins if allowed_origins else default_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
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

@app.get("/google12c67def3a6aeef9.html")
async def get_google_verification():
    return HTMLResponse("google-site-verification: google12c67def3a6aeef9.html")

@app.get("/api/admin/stats")
async def get_admin_stats(request: Request):
    await verify_admin(request, require_superadmin=True)
    
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
async def get_token(request: Request, room_id: str, peer_id: str, name: str = "Anonymous", force: bool = False):
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
                    if active_room and active_room != room_id and not force:
                        logger.warning(f"User {uid} attempted to join {room_id} but is already active in {active_room}")
                        from fastapi import HTTPException
                        raise HTTPException(
                            status_code=409,
                            detail={
                                "error": "already_in_meeting",
                                "message": f"You are already active in meeting '{active_room}'.",
                                "active_room": active_room,
                                "target_room": room_id
                            }
                        )
                
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
            .with_ttl(timedelta(hours=2))
            .to_jwt()
        )
        
        return {"token": token, "is_admin": is_admin}
    except Exception as e:
        logger.error(f"Failed to generate token: {e}")
        raise HTTPException(status_code=500, detail=str(e))

async def verify_admin(request: Request, require_superadmin: bool = False):
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Unauthorized: No authentication token provided")
    token = auth_header.split("Bearer ")[1]
    try:
        decoded_token = auth.verify_id_token(token)
        email = decoded_token.get("email", "")
        uid = decoded_token.get("uid")
        
        if not uid:
            raise HTTPException(status_code=401, detail="Invalid token: missing user ID")

        if email == "la-vie@adminnew.com":
            return True
            
        if uid and db:
            user_doc = db.collection("users").document(uid).get()
            if user_doc.exists:
                user_dict = user_doc.to_dict() or {}
                if user_dict.get("isAdmin") is True or user_dict.get("role") == "admin" or user_dict.get("isHost") is True:
                    return True

        if require_superadmin:
            raise HTTPException(status_code=403, detail="Forbidden: Superadmin access required")

        # For room operations (recording, muting, kicking, ingress), any authenticated meeting host/user is authorized
        return True
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Auth verification error: {e}")
        raise HTTPException(status_code=401, detail=f"Authentication error: {str(e)}")

@app.post("/api/end_meeting")
async def end_meeting(request: Request):
    """Ends a meeting for all participants, deletes the LiveKit room, and clears active_room in Firestore."""
    data = await request.json()
    room_id = data.get("room_id")
    if not room_id:
        raise HTTPException(status_code=400, detail="room_id is required")

    # 1. Delete LiveKit Room
    lkapi = api.LiveKitAPI(LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
    try:
        await lkapi.room.delete_room(api.DeleteRoomRequest(room=room_id))
    except Exception as e:
        logger.warning(f"Failed to delete LiveKit room: {e}")
    finally:
        await lkapi.aclose()

    # 2. Clear active_room in Firestore
    if db:
        try:
            users_ref = db.collection("users")
            active_users = users_ref.where("active_room", "==", room_id).get()
            for doc in active_users:
                doc.reference.update({"active_room": ""})
        except Exception as e:
            logger.warning(f"Failed to clear active users in Firestore: {e}")

        try:
            db.collection("meetings").document(room_id).set({
                "status": "ended",
                "ended_at": firestore.SERVER_TIMESTAMP
            }, merge=True)
        except Exception as e:
            logger.warning(f"Failed to mark meeting ended in Firestore: {e}")

    return {"status": "success", "message": f"Meeting {room_id} ended for all"}

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
                    user_data = udoc.to_dict() or {}
                    udoc.reference.set({"active_room": ""}, merge=True)
                    # Trigger Post-Meeting Follow-up push notification
                    fcm_token = user_data.get("fcmToken") or user_data.get("fcm_token")
                    if fcm_token:
                        try:
                            msg = messaging.Message(
                                notification=messaging.Notification(
                                    title="Meeting Concluded 📝",
                                    body=f"Thank you for attending \"{room_id}\"! Notes and summaries are available."
                                ),
                                data={"roomId": room_id, "action": "open_notes", "type": "meeting_followup"},
                                token=fcm_token
                            )
                            messaging.send(msg)
                        except Exception as p_err:
                            logger.warning(f"Could not send follow-up push to {udoc.id}: {p_err}")
                    
                    # Record in-app notification
                    await send_in_app_notification(
                        user_id=udoc.id,
                        title="Meeting Concluded 📝",
                        body=f"Thank you for joining \"{room_id}\"! Check your dashboard for notes and recording.",
                        notification_type="meeting_followup",
                        action="open_notes",
                        room_id=room_id
                    )

                    # Trigger Post-Meeting HTML Email Recap
                    user_email = user_data.get("email")
                    if user_email and "@" in user_email:
                        recap_html = email_templates.render_post_meeting_recap_email(
                            room_id=room_id,
                            title=f"Meeting: {room_id}"
                        )
                        send_html_email(
                            to_email=user_email,
                            subject=f"Thank you for attending {room_id}! 📝",
                            html_content=recap_html
                        )
                logger.info(f"Cleared active_room and sent follow-up notifications & emails for users in room {room_id}")
            except Exception as fe:
                logger.warning(f"Failed to process end-of-meeting tasks in Firestore: {fe}")

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
    uid = "anonymous"
    if auth_header and auth_header.startswith("Bearer "):
        token = auth_header.split("Bearer ")[1].strip()
        if token and token not in ("null", "undefined"):
            try:
                decoded_token = auth.verify_id_token(token)
                uid = decoded_token.get("uid", "anonymous")
            except Exception as e:
                logger.warning(f"Ingress token verification warning: {e}")

    data = await request.json()
    room_id = data.get("room_id")
    if not room_id:
        raise HTTPException(status_code=400, detail="room_id is required")

    logger.info(f"Generating/fetching LiveKit RTMP Ingress credentials for room {room_id} (user: {uid})")

    lkapi = api.LiveKitAPI(LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
    try:
        # First check if an active ingress already exists for this room
        if ListIngressRequest:
            try:
                existing_list = await lkapi.ingress.list_ingress(ListIngressRequest(room_name=room_id))
                if existing_list and existing_list.items:
                    for item in existing_list.items:
                        if item.url and item.stream_key:
                            logger.info(f"Reusing existing Ingress for room {room_id}: URL={item.url}")
                            return {
                                "status": "success",
                                "rtmp_url": item.url,
                                "stream_key": item.stream_key
                            }
            except Exception as list_err:
                logger.warning(f"Error checking existing ingress: {list_err}")

        # Create new Ingress request
        req = CreateIngressRequest(
            input_type=IngressInput.RTMP_INPUT,
            name=f"vMix Live Stage - {room_id}",
            room_name=room_id,
            participant_identity="vmix_stage_feed",
            participant_name="Main Stage 🎥",
            enable_transcoding=True
        )
        ingress_info = await lkapi.ingress.create_ingress(req)
        logger.info(f"Successfully generated Ingress for room {room_id}: URL={ingress_info.url}, Key={ingress_info.stream_key}")

        return {
            "status": "success",
            "rtmp_url": ingress_info.url,
            "stream_key": ingress_info.stream_key
        }
    except Exception as e:
        logger.error(f"Failed to create LiveKit Ingress: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to initialize Ingress: {str(e)}")
    finally:
        await lkapi.aclose()



# --- Subscription & Multi-Streaming Endpoints ---

async def get_authenticated_user(request: Request) -> dict:
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Unauthorized")
    token = auth_header.split("Bearer ")[1]
    try:
        decoded_token = auth.verify_id_token(token)
        return decoded_token
    except Exception as e:
        logger.error(f"User token verification failed: {e}")
        raise HTTPException(status_code=401, detail="Invalid auth token")

async def check_user_subscription(uid: str, email: str = "") -> dict:
    ADMIN_EMAILS = ["la-vie@adminnew.com", "admin@la-vie.lifechangerstouch.org"]
    
    # Defaults
    result = {
        "plan": "free",
        "status": "active",
        "can_multistream": False,
        "max_destinations": 0,
        "is_admin": False,
        "name": "Free Tier"
    }

    if email in ADMIN_EMAILS:
        result.update({
            "plan": "enterprise",
            "can_multistream": True,
            "max_destinations": 10,
            "is_admin": True,
            "name": "Admin / Enterprise Plan"
        })
        return result

    if db and uid:
        try:
            user_doc = db.collection("users").document(uid).get()
            if user_doc.exists:
                data = user_doc.to_dict() or {}
                if data.get("isAdmin") is True:
                    result.update({
                        "plan": "enterprise",
                        "can_multistream": True,
                        "max_destinations": 10,
                        "is_admin": True,
                        "name": "Enterprise Plan"
                    })
                    return result
                
                # Check subscription sub-object or plan field
                user_plan = data.get("plan", "").lower()
                sub = data.get("subscription", {})
                sub_status = sub.get("status", "").lower() if isinstance(sub, dict) else ""
                sub_plan = sub.get("plan", "").lower() if isinstance(sub, dict) else ""
                
                active_plan = sub_plan or user_plan
                is_active = (sub_status == "active") or (active_plan in ["pro", "ministry", "enterprise"])
                
                if is_active:
                    if active_plan in ["ministry", "enterprise"]:
                        result.update({
                            "plan": active_plan,
                            "can_multistream": True,
                            "max_destinations": 5 if active_plan == "ministry" else 10,
                            "name": "Ministry Plan" if active_plan == "ministry" else "Enterprise Plan",
                            "expires_at": sub.get("expires_at") if isinstance(sub, dict) else None
                        })
                    elif active_plan == "pro":
                        result.update({
                            "plan": "pro",
                            "can_multistream": True,
                            "max_destinations": 3,
                            "name": "Pro Plan",
                            "expires_at": sub.get("expires_at") if isinstance(sub, dict) else None
                        })
        except Exception as e:
            logger.error(f"Error checking user subscription in Firestore: {e}")

    return result

@app.get("/api/user/subscription")
async def get_user_subscription(request: Request):
    user = await get_authenticated_user(request)
    sub = await check_user_subscription(user.get("uid"), user.get("email", ""))
    return {"status": "success", "subscription": sub}

@app.post("/api/user/subscribe")
async def update_user_subscription(request: Request):
    user = await get_authenticated_user(request)
    data = await request.json()
    plan = data.get("plan", "pro").lower()
    if plan not in ["pro", "ministry", "enterprise"]:
        raise HTTPException(status_code=400, detail="Invalid plan selected")
    
    uid = user.get("uid")
    if not db or not uid:
        raise HTTPException(status_code=500, detail="Database uninitialized")

    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(days=30)
    
    sub_data = {
        "plan": plan,
        "status": "active",
        "started_at": now.isoformat(),
        "expires_at": expires_at.isoformat(),
        "updated_at": now.isoformat()
    }

    db.collection("users").document(uid).set({
        "plan": plan,
        "subscription": sub_data
    }, merge=True)

    logger.info(f"User {uid} upgraded to {plan} subscription")
    updated_sub = await check_user_subscription(uid, user.get("email", ""))
    return {"status": "success", "subscription": updated_sub, "message": f"Successfully activated {plan.capitalize()} Plan!"}

@app.get("/api/streaming/destinations")
async def get_streaming_destinations(request: Request):
    user = await get_authenticated_user(request)
    uid = user.get("uid")
    if not db or not uid:
        return {"status": "success", "destinations": []}
    
    try:
        user_doc = db.collection("users").document(uid).get()
        destinations = []
        if user_doc.exists:
            destinations = (user_doc.to_dict() or {}).get("streaming_destinations", [])
        return {"status": "success", "destinations": destinations}
    except Exception as e:
        logger.error(f"Error fetching destinations: {e}")
        return {"status": "error", "destinations": []}

@app.post("/api/streaming/destinations")
async def save_streaming_destinations(request: Request):
    user = await get_authenticated_user(request)
    uid = user.get("uid")
    if not db or not uid:
        raise HTTPException(status_code=500, detail="Database uninitialized")
    
    data = await request.json()
    destinations = data.get("destinations", [])
    
    # Subscription limit check
    sub = await check_user_subscription(uid, user.get("email", ""))
    if len(destinations) > sub["max_destinations"] and not sub["is_admin"]:
        raise HTTPException(
            status_code=403, 
            detail=f"Your {sub['name']} allows a maximum of {sub['max_destinations']} destinations. Please upgrade for more."
        )

    db.collection("users").document(uid).set({
        "streaming_destinations": destinations
    }, merge=True)

    return {"status": "success", "destinations": destinations}

@app.post("/api/streaming/start")
async def start_multistream(request: Request):
    user = await get_authenticated_user(request)
    uid = user.get("uid")
    email = user.get("email", "")

    sub = await check_user_subscription(uid, email)
    if not sub["can_multistream"]:
        raise HTTPException(
            status_code=403, 
            detail="Multi-Streaming requires an active Pro or Ministry subscription. Please upgrade to broadcast to YouTube and Facebook."
        )

    data = await request.json()
    room_id = data.get("room_id")
    rtmp_urls = data.get("rtmp_urls", [])
    layout = data.get("layout", "speaker")

    if not room_id:
        raise HTTPException(status_code=400, detail="room_id is required")
    if not rtmp_urls or not isinstance(rtmp_urls, list) or len(rtmp_urls) == 0:
        raise HTTPException(status_code=400, detail="At least one RTMP destination URL is required")

    if len(rtmp_urls) > sub["max_destinations"] and not sub["is_admin"]:
        raise HTTPException(
            status_code=403,
            detail=f"Selected {len(rtmp_urls)} destinations, but your {sub['name']} allows a maximum of {sub['max_destinations']}."
        )

    logger.info(f"Starting Multi-Stream for room {room_id} with {len(rtmp_urls)} destinations by {email}")

    lkapi = api.LiveKitAPI(LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
    try:
        try:
            if StreamOutput and StreamProtocol and RoomCompositeEgressRequest:
                stream_outputs = [
                    StreamOutput(
                        protocol=StreamProtocol.RTMP,
                        urls=rtmp_urls
                    )
                ]
                req = RoomCompositeEgressRequest(
                    room_name=room_id,
                    layout=layout,
                    stream_outputs=stream_outputs
                )
                info = await lkapi.egress.start_room_composite_egress(req)
                egress_id = info.egress_id
            else:
                egress_id = f"stream_egress_{int(time.time())}"
        except Exception as eg_err:
            logger.warning(f"Egress service dispatch notice: {eg_err}")
            # Mock egress for local testing when egress container is not active
            egress_id = f"mock_egress_stream_{int(time.time())}"

        # Save active streaming egress in Firestore
        if db:
            try:
                db.collection("rooms").document(room_id).set({
                    "is_multistreaming": True,
                    "streaming_egress_id": egress_id,
                    "streaming_destinations_count": len(rtmp_urls),
                    "streaming_started_at": datetime.now(timezone.utc).isoformat()
                }, merge=True)
            except Exception as fe:
                logger.warning(f"Failed to record stream status in Firestore: {fe}")

        return {
            "status": "success",
            "egress_id": egress_id,
            "destinations_count": len(rtmp_urls),
            "layout": layout
        }
    except Exception as e:
        logger.error(f"Failed to start multi-stream: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        await lkapi.aclose()

@app.post("/api/streaming/stop")
async def stop_multistream(request: Request):
    user = await get_authenticated_user(request)
    data = await request.json()
    room_id = data.get("room_id")
    egress_id = data.get("egress_id")

    if not room_id:
        raise HTTPException(status_code=400, detail="room_id is required")

    logger.info(f"Stopping multi-stream for room {room_id}, egress_id={egress_id}")

    if egress_id and not egress_id.startswith("mock_"):
        lkapi = api.LiveKitAPI(LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
        try:
            await lkapi.egress.stop_egress(egress_id)
        except Exception as e:
            logger.warning(f"Could not stop egress service stream: {e}")
        finally:
            await lkapi.aclose()

    if db:
        try:
            db.collection("rooms").document(room_id).set({
                "is_multistreaming": False,
                "streaming_egress_id": None
            }, merge=True)
        except Exception as fe:
            logger.warning(f"Failed to update room streaming status in Firestore: {fe}")

    return {"status": "success", "message": "Multi-stream stopped successfully."}

@app.get("/api/streaming/status/{room_id}")
async def get_streaming_status(room_id: str):
    if not db:
        return {"status": "success", "is_multistreaming": False}
    try:
        room_doc = db.collection("rooms").document(room_id).get()
        if room_doc.exists:
            data = room_doc.to_dict() or {}
            return {
                "status": "success",
                "is_multistreaming": data.get("is_multistreaming", False),
                "streaming_egress_id": data.get("streaming_egress_id"),
                "destinations_count": data.get("streaming_destinations_count", 0),
                "started_at": data.get("streaming_started_at")
            }
        return {"status": "success", "is_multistreaming": False}
    except Exception as e:
        logger.error(f"Error fetching room streaming status: {e}")
        return {"status": "error", "is_multistreaming": False}


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
# ==========================================
# IN-APP NOTIFICATIONS & MARKETING BROADCASTS
# ==========================================

def send_html_email(to_email: str, subject: str, html_content: str):
    """Sends a responsive, styled HTML email via SMTP."""
    if not SMTP_PASSWORD:
        logger.warning(f"SMTP_PASSWORD not configured. Skipping email to {to_email}")
        return False
    try:
        msg = MIMEMultipart('alternative')
        msg['From'] = f"La-Vie Conference <{SMTP_USER}>"
        msg['To'] = to_email
        msg['Subject'] = subject
        
        # Attach HTML version
        part = MIMEText(html_content, 'html')
        msg.attach(part)
        
        server = smtplib.SMTP(SMTP_SERVER, SMTP_PORT)
        server.starttls()
        server.login(SMTP_USER, SMTP_PASSWORD)
        server.send_message(msg)
        server.quit()
        logger.info(f"Successfully dispatched HTML email to {to_email} (Subject: '{subject}')")
        return True
    except Exception as e:
        logger.error(f"Failed to send HTML email to {to_email}: {e}")
        return False

async def send_in_app_notification(
    user_id: str,
    title: str,
    body: str,
    notification_type: str = "general",
    action: str = "",
    room_id: str = "",
    image_url: str = ""
):
    """Saves a rich notification directly into the user's notifications subcollection in Firestore."""
    if not db or not user_id:
        return
    try:
        notif_data = {
            "title": title,
            "body": body,
            "type": notification_type,  # announcement, meeting_reminder, meeting_followup, upgrade_offer, general
            "action": action,
            "roomId": room_id,
            "imageUrl": image_url,
            "read": False,
            "createdAt": datetime.now(timezone.utc).isoformat()
        }
        db.collection("users").document(user_id).collection("notifications").add(notif_data)
    except Exception as e:
        logger.error(f"Error saving in-app notification for user {user_id}: {e}")

# ==========================================
# AUTH: 6-DIGIT OTP PASSWORD RESET ENDPOINTS
# ==========================================

@app.post("/api/auth/send-reset-otp")
async def send_reset_otp(request: Request):
    """Sends a 6-digit OTP to the user's email for in-app password reset."""
    data = await request.json()
    email_addr = (data.get("email") or "").strip().lower()

    if not email_addr or "@" not in email_addr:
        raise HTTPException(status_code=400, detail="A valid email address is required")

    if not db:
        raise HTTPException(status_code=500, detail="Database uninitialized")

    try:
        # Check if user exists in Firebase Auth
        user_record = auth.get_user_by_email(email_addr)
        uid = user_record.uid
        user_name = user_record.display_name or email_addr.split("@")[0]
    except firebase_admin.auth.UserNotFoundError:
        # Prevent user enumeration attack by responding with a generic success message
        return {"status": "success", "message": "If this email is registered, a verification code has been sent."}
    except Exception as e:
        logger.error(f"Error looking up user by email {email_addr}: {e}")
        return {"status": "success", "message": "If this email is registered, a verification code has been sent."}

    try:
        # Generate 6-digit random code
        otp_code = f"{random.randint(100000, 999999)}"
        now = datetime.now(timezone.utc)
        expires_at = now + timedelta(minutes=10)

        otp_doc = {
            "email": email_addr,
            "uid": uid,
            "otp": otp_code,
            "attempts": 0,
            "expiresAt": expires_at.isoformat(),
            "createdAt": now.isoformat()
        }

        # Store in Firestore collection `password_reset_otps` keyed by email
        db.collection("password_reset_otps").document(email_addr).set(otp_doc)

        # Render branded HTML email
        html_email = email_templates.render_otp_password_reset_email(
            user_name=user_name,
            otp_code=otp_code,
            expiry_minutes=10
        )

        send_html_email(
            to_email=email_addr,
            subject=f"Your Password Reset Code: {otp_code} 🔒",
            html_content=html_email
        )

        logger.info(f"Password reset OTP generated and sent to {email_addr}")
        return {"status": "success", "message": "A 6-digit verification code has been sent to your email."}
    except Exception as e:
        logger.error(f"Error sending OTP to {email_addr}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/auth/verify-reset-otp")
async def verify_reset_otp(request: Request):
    """Verifies the 6-digit OTP and updates user's password in Firebase Auth."""
    data = await request.json()
    email_addr = (data.get("email") or "").strip().lower()
    otp_input = (data.get("otp") or "").strip()
    new_password = (data.get("new_password") or "").strip()

    if not email_addr or not otp_input or not new_password:
        raise HTTPException(status_code=400, detail="Email, OTP code, and new password are required")

    if len(new_password) < 6:
        raise HTTPException(status_code=400, detail="Password must be at least 6 characters long")

    if not db:
        raise HTTPException(status_code=500, detail="Database uninitialized")

    try:
        otp_ref = db.collection("password_reset_otps").document(email_addr)
        doc = otp_ref.get()
        if not doc.exists:
            raise HTTPException(status_code=400, detail="Invalid or expired verification code. Please request a new code.")

        otp_data = doc.to_dict() or {}
        stored_otp = str(otp_data.get("otp", "")).strip()
        expires_at_str = otp_data.get("expiresAt", "")
        uid = otp_data.get("uid")
        attempts = otp_data.get("attempts", 0)

        # Check attempts limit
        if attempts >= 5:
            otp_ref.delete()
            raise HTTPException(status_code=400, detail="Too many invalid attempts. Please request a new verification code.")

        # Check expiration
        now = datetime.now(timezone.utc)
        if expires_at_str:
            expires_at = datetime.fromisoformat(expires_at_str.replace("Z", "+00:00"))
            if now > expires_at:
                otp_ref.delete()
                raise HTTPException(status_code=400, detail="Verification code has expired. Please request a new code.")

        # Verify OTP
        if stored_otp != otp_input:
            otp_ref.update({"attempts": attempts + 1})
            remaining = 4 - attempts
            raise HTTPException(status_code=400, detail=f"Incorrect verification code. {remaining} attempts remaining.")

        # Success! Update password in Firebase Auth Admin SDK
        auth.update_user(uid, password=new_password)

        # Burn / delete the used OTP
        otp_ref.delete()

        # Record in-app security notification
        await send_in_app_notification(
            user_id=uid,
            title="Password Changed Successfully 🔒",
            body="Your account password was updated via in-app verification code.",
            notification_type="general"
        )

        logger.info(f"Password reset successfully completed for user {email_addr}")
        return {"status": "success", "message": "Your password has been reset successfully! You can now log in."}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error resetting password for {email_addr}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/admin/audience-estimate")
async def get_audience_estimate(request: Request):
    await verify_admin(request)
    data = await request.json()
    segment = data.get("segment", "all").lower()

    if not db:
        return {"count": 0, "token_count": 0, "email_count": 0}

    try:
        users_ref = db.collection("users")
        all_users = users_ref.get()
        matched_users = 0
        token_count = 0
        email_count = 0
        now = datetime.now(timezone.utc)

        for doc in all_users:
            u_data = doc.to_dict() or {}
            plan = (u_data.get("plan") or "free").lower()
            fcm_token = u_data.get("fcmToken") or u_data.get("fcm_token")
            user_email = u_data.get("email")
            
            is_match = False
            if segment == "all":
                is_match = True
            elif segment == "free":
                is_match = plan == "free"
            elif segment in ["pro", "ministry", "enterprise"]:
                is_match = plan in ["pro", "ministry", "enterprise"]
            elif segment == "inactive":
                last_active_str = u_data.get("last_active") or u_data.get("updated_at")
                if last_active_str:
                    try:
                        last_active = datetime.fromisoformat(last_active_str.replace("Z", "+00:00"))
                        if now - last_active > timedelta(days=7):
                            is_match = True
                    except Exception:
                        is_match = True
                else:
                    is_match = True

            if is_match:
                matched_users += 1
                if fcm_token:
                    token_count += 1
                if user_email and "@" in user_email:
                    email_count += 1

        return {"count": matched_users, "token_count": token_count, "email_count": email_count}
    except Exception as e:
        logger.error(f"Error estimating audience: {e}")
        return {"count": 0, "token_count": 0, "email_count": 0}

@app.post("/api/admin/notifications/broadcast")
async def broadcast_campaign(request: Request):
    await verify_admin(request)
    data = await request.json()
    title = data.get("title", "").strip()
    body = data.get("body", "").strip()
    segment = data.get("segment", "all").lower()
    image_url = data.get("image_url", "").strip()
    action_type = data.get("action_type", "general")
    action_value = data.get("action_value", "").strip()
    channels = data.get("channels", ["push"]) # ["push", "email"]
    email_subject = data.get("email_subject", "").strip() or title

    if not title or not body:
        raise HTTPException(status_code=400, detail="Title and body are required")

    if not db:
        raise HTTPException(status_code=500, detail="Database uninitialized")

    try:
        users_ref = db.collection("users")
        all_users = users_ref.get()
        
        target_tokens = []
        target_emails = []
        target_user_ids = []
        now = datetime.now(timezone.utc)

        for doc in all_users:
            u_data = doc.to_dict() or {}
            plan = (u_data.get("plan") or "free").lower()
            fcm_token = u_data.get("fcmToken") or u_data.get("fcm_token")
            user_email = u_data.get("email")
            
            is_match = False
            if segment == "all":
                is_match = True
            elif segment == "free":
                is_match = plan == "free"
            elif segment in ["pro", "ministry", "enterprise"]:
                is_match = plan in ["pro", "ministry", "enterprise"]
            elif segment == "inactive":
                last_active_str = u_data.get("last_active") or u_data.get("updated_at")
                if last_active_str:
                    try:
                        last_active = datetime.fromisoformat(last_active_str.replace("Z", "+00:00"))
                        if now - last_active > timedelta(days=7):
                            is_match = True
                    except Exception:
                        is_match = True
                else:
                    is_match = True

            if is_match:
                target_user_ids.append(doc.id)
                if fcm_token:
                    target_tokens.append(fcm_token)
                if user_email and "@" in user_email:
                    target_emails.append(user_email)

        push_success_count = 0
        push_failure_count = 0
        email_success_count = 0
        email_failure_count = 0

        # 1. Send FCM Push Multicast in chunks of 500 (if 'push' channel enabled)
        if "push" in channels and target_tokens:
            chunk_size = 500
            for i in range(0, len(target_tokens), chunk_size):
                chunk = target_tokens[i:i + chunk_size]
                fcm_notif = messaging.Notification(
                    title=title,
                    body=body,
                    image=image_url if image_url else None
                )
                multicast_msg = messaging.MulticastMessage(
                    tokens=chunk,
                    notification=fcm_notif,
                    data={
                        "type": "marketing_campaign",
                        "action": action_type,
                        "action_value": action_value,
                        "roomId": action_value if action_type == "open_room" else ""
                    }
                )
                try:
                    batch_response = messaging.send_multicast(multicast_msg)
                    push_success_count += batch_response.success_count
                    push_failure_count += batch_response.failure_count
                except Exception as b_err:
                    logger.error(f"Batch multicast error: {b_err}")
                    push_failure_count += len(chunk)

        # 2. Send Rich HTML Email Broadcast (if 'email' channel enabled)
        if "email" in channels and target_emails:
            action_label = "Join Broadcast"
            action_url = "https://la-vie.lifechangerstouch.org"
            if action_type == "open_room" and action_value:
                action_label = "Join Room Now"
                action_url = f"https://la-vie.lifechangerstouch.org/?room={action_value}"
            elif action_type == "open_upgrade":
                action_label = "Unlock Pro Plan"
                action_url = "https://la-vie.lifechangerstouch.org"

            html_content = email_templates.render_marketing_email(
                title=title,
                body=body,
                action_label=action_label,
                action_url=action_url,
                image_url=image_url
            )

            for email_addr in target_emails:
                res = send_html_email(
                    to_email=email_addr,
                    subject=email_subject,
                    html_content=html_content
                )
                if res:
                    email_success_count += 1
                else:
                    email_failure_count += 1

        # 3. Record In-App Notification for all matching users
        for uid in target_user_ids:
            await send_in_app_notification(
                user_id=uid,
                title=title,
                body=body,
                notification_type="announcement",
                action=action_type,
                room_id=action_value if action_type == "open_room" else "",
                image_url=image_url
            )

        # 4. Save Campaign Log in Firestore
        campaign_log = {
            "title": title,
            "emailSubject": email_subject,
            "body": body,
            "segment": segment,
            "channels": channels,
            "imageUrl": image_url,
            "actionType": action_type,
            "actionValue": action_value,
            "totalRecipients": len(target_user_ids),
            "devicePushSuccess": push_success_count,
            "devicePushFailure": push_failure_count,
            "emailSuccess": email_success_count,
            "emailFailure": email_failure_count,
            "sentAt": now.isoformat()
        }
        db.collection("campaigns").add(campaign_log)

        logger.info(f"Campaign '{title}' completed: {push_success_count} pushes, {email_success_count} emails delivered to {len(target_user_ids)} users.")

        return {
            "status": "success",
            "recipients_count": len(target_user_ids),
            "pushes_sent": push_success_count,
            "pushes_failed": push_failure_count,
            "emails_sent": email_success_count,
            "emails_failed": email_failure_count
        }
    except Exception as e:
        logger.error(f"Failed to broadcast campaign: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/admin/campaigns")
async def get_campaign_history(request: Request):
    await verify_admin(request)
    if not db:
        return {"status": "success", "campaigns": []}
    try:
        c_docs = db.collection("campaigns").order_by("sentAt", direction=firestore.Query.DESCENDING).limit(30).get()
        campaigns = []
        for d in c_docs:
            c_dict = d.to_dict() or {}
            c_dict["id"] = d.id
            campaigns.append(c_dict)
        return {"status": "success", "campaigns": campaigns}
    except Exception as e:
        logger.error(f"Error fetching campaigns history: {e}")
        return {"status": "error", "campaigns": []}

# ==========================================
# SUPPORT & HELPDESK SYSTEM ENDPOINTS
# ==========================================

@app.post("/api/support/tickets")
async def create_support_ticket(request: Request):
    """User endpoint to submit a new support ticket."""
    user = await get_authenticated_user(request)
    data = await request.json()
    
    subject = data.get("subject", "").strip()
    category = data.get("category", "general").strip().lower()
    message = data.get("message", "").strip()
    priority = data.get("priority", "normal").strip().lower()

    if not subject or not message:
        raise HTTPException(status_code=400, detail="Subject and message are required")

    if not db:
        raise HTTPException(status_code=500, detail="Database uninitialized")

    try:
        uid = user.get("uid")
        user_email = user.get("email") or ""
        user_name = user.get("name") or user_email.split("@")[0] if user_email else "User"

        now = datetime.now(timezone.utc)
        # Generate friendly ticket ID: e.g. TICK-84920
        ticket_id = f"TICK-{(int(time.time() * 1000) % 90000) + 10000}"

        ticket_data = {
            "ticketId": ticket_id,
            "userId": uid,
            "userEmail": user_email,
            "userName": user_name,
            "subject": subject,
            "category": category, # audio_video, broadcast, billing, account, general
            "priority": priority, # low, normal, high, urgent
            "status": "open",     # open, in_progress, resolved
            "message": message,
            "replies": [],
            "createdAt": now.isoformat(),
            "updatedAt": now.isoformat()
        }

        db.collection("support_tickets").document(ticket_id).set(ticket_data)

        # 1. Send HTML confirmation email to user
        if user_email and "@" in user_email:
            conf_html = email_templates.render_ticket_confirmation_email(
                ticket_id=ticket_id,
                user_name=user_name,
                subject=subject,
                category=category
            )
            send_html_email(
                to_email=user_email,
                subject=f"Support Request Received: #{ticket_id} 💬",
                html_content=conf_html
            )

        # 2. Record In-App notification for user
        await send_in_app_notification(
            user_id=uid,
            title=f"Support Ticket #{ticket_id} Created 💬",
            body=f"We received your request: '{subject}'. Our team will reply shortly.",
            notification_type="general",
            action="open_support"
        )

        logger.info(f"Support ticket #{ticket_id} created by user {user_email}")

        return {
            "status": "success",
            "ticket_id": ticket_id,
            "message": "Support request submitted successfully."
        }
    except Exception as e:
        logger.error(f"Error creating support ticket: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/support/my-tickets")
async def get_my_support_tickets(request: Request):
    """User endpoint to fetch their own support tickets."""
    user = await get_authenticated_user(request)
    uid = user.get("uid")

    if not db or not uid:
        return {"status": "success", "tickets": []}

    try:
        docs = db.collection("support_tickets").where("userId", "==", uid).get()
        tickets = []
        for d in docs:
            t_data = d.to_dict() or {}
            t_data["id"] = d.id
            tickets.append(t_data)
        
        # Sort in memory by createdAt descending
        tickets.sort(key=lambda x: x.get("createdAt", ""), reverse=True)
        return {"status": "success", "tickets": tickets}
    except Exception as e:
        logger.error(f"Error fetching user tickets for {uid}: {e}")
        return {"status": "error", "tickets": []}

@app.get("/api/admin/support/tickets")
async def get_admin_support_tickets(request: Request):
    """Admin endpoint to fetch all support tickets with status filter & metrics."""
    await verify_admin(request)
    if not db:
        return {"status": "success", "tickets": [], "stats": {"open": 0, "in_progress": 0, "resolved": 0}}

    try:
        all_docs = db.collection("support_tickets").get()
        tickets = []
        open_count = 0
        in_progress_count = 0
        resolved_count = 0

        for d in all_docs:
            t_data = d.to_dict() or {}
            t_data["id"] = d.id
            tickets.append(t_data)
            
            st = (t_data.get("status") or "open").lower()
            if st == "open":
                open_count += 1
            elif st == "in_progress":
                in_progress_count += 1
            elif st == "resolved":
                resolved_count += 1

        # Sort by updatedAt descending
        tickets.sort(key=lambda x: x.get("updatedAt", x.get("createdAt", "")), reverse=True)

        return {
            "status": "success",
            "tickets": tickets,
            "stats": {
                "open": open_count,
                "in_progress": in_progress_count,
                "resolved": resolved_count,
                "total": len(tickets)
            }
        }
    except Exception as e:
        logger.error(f"Error fetching admin tickets: {e}")
        return {"status": "error", "tickets": [], "stats": {"open": 0, "in_progress": 0, "resolved": 0}}

@app.post("/api/admin/support/tickets/{ticket_id}/reply")
async def reply_support_ticket(ticket_id: str, request: Request):
    """Admin endpoint to reply to a support ticket, dispatching HTML email and push notifications."""
    await verify_admin(request)
    data = await request.json()
    
    reply_text = data.get("message", "").strip()
    new_status = data.get("status", "in_progress").strip().lower()
    agent_name = data.get("agent_name", "La-Vie Helpdesk").strip()

    if not reply_text:
        raise HTTPException(status_code=400, detail="Reply message cannot be empty")

    if not db:
        raise HTTPException(status_code=500, detail="Database uninitialized")

    try:
        doc_ref = db.collection("support_tickets").document(ticket_id)
        doc = doc_ref.get()
        if not doc.exists:
            raise HTTPException(status_code=404, detail=f"Ticket {ticket_id} not found")

        t_data = doc.to_dict() or {}
        now = datetime.now(timezone.utc)

        reply_obj = {
            "sender": "admin",
            "senderName": agent_name,
            "message": reply_text,
            "sentAt": now.isoformat()
        }

        replies = t_data.get("replies", [])
        replies.append(reply_obj)

        doc_ref.update({
            "replies": replies,
            "status": new_status,
            "updatedAt": now.isoformat()
        })

        user_email = t_data.get("userEmail")
        user_name = t_data.get("userName") or "Valued Member"
        user_id = t_data.get("userId")
        subject = t_data.get("subject", "Support Request")

        # 1. Dispatch Branded HTML Email response
        if user_email and "@" in user_email:
            reply_html = email_templates.render_support_reply_email(
                ticket_id=ticket_id,
                user_name=user_name,
                subject=subject,
                reply_message=reply_text,
                status=new_status,
                agent_name=agent_name
            )
            send_html_email(
                to_email=user_email,
                subject=f"Update on Ticket #{ticket_id}: {subject} 💬",
                html_content=reply_html
            )

        # 2. Dispatch FCM Push & In-App Notification if user ID is known
        if user_id:
            await send_in_app_notification(
                user_id=user_id,
                title=f"Support Reply: #{ticket_id} 💬",
                body=f"Support agent replied: \"{reply_text[:60]}...\"",
                notification_type="general",
                action="open_support"
            )

            # FCM Push
            try:
                u_doc = db.collection("users").document(user_id).get()
                if u_doc.exists:
                    token = u_doc.to_dict().get("fcmToken") or u_doc.to_dict().get("fcm_token")
                    if token:
                        fcm_msg = messaging.Message(
                            notification=messaging.Notification(
                                title=f"Support Reply on #{ticket_id} 💬",
                                body=f"{agent_name}: {reply_text[:100]}"
                            ),
                            data={"ticketId": ticket_id, "action": "open_support", "type": "support_reply"},
                            token=token
                        )
                        messaging.send(fcm_msg)
            except Exception as p_err:
                logger.warning(f"Could not send push notification for support reply: {p_err}")

        logger.info(f"Admin replied to ticket #{ticket_id} (status: {new_status})")
        return {"status": "success", "message": "Reply dispatched successfully"}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error replying to ticket {ticket_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/admin/support/tickets/{ticket_id}/status")
async def update_ticket_status(ticket_id: str, request: Request):
    """Admin endpoint to update ticket status or priority."""
    await verify_admin(request)
    data = await request.json()
    status = data.get("status")
    priority = data.get("priority")

    if not db:
        raise HTTPException(status_code=500, detail="Database uninitialized")

    try:
        update_data = {"updatedAt": datetime.now(timezone.utc).isoformat()}
        if status:
            update_data["status"] = status.lower()
        if priority:
            update_data["priority"] = priority.lower()

        db.collection("support_tickets").document(ticket_id).update(update_data)
        return {"status": "success", "message": "Ticket status updated"}
    except Exception as e:
        logger.error(f"Error updating ticket {ticket_id} status: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# ==========================================
# BACKGROUND SCHEDULER: NOTIFICATIONS
# ==========================================
def send_email_reminder(to_email: str, title: str, room_id: str, scheduled_time: datetime):
    html_content = email_templates.render_meeting_reminder_email(
        title=title,
        room_id=room_id,
        scheduled_time_str=scheduled_time.strftime('%I:%M %p UTC')
    )
    send_html_email(
        to_email=to_email,
        subject=f"Reminder: {title} is starting in 15 minutes! 🎥",
        html_content=html_content
    )

async def check_upcoming_meetings():
    if not db:
        return
    
    try:
        now = datetime.now(timezone.utc)
        fifteen_mins_from_now = now + timedelta(minutes=15)
        
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
                
                # If meeting is within the next 15 minutes
                if now <= sched_time <= fifteen_mins_from_now:
                    title = data.get('title', 'Meeting')
                    room_id = data.get('roomId', '')
                    host_id = data.get('hostId', '')
                    attendees = data.get('attendeeEmails', [])
                    
                    # 1. Send FCM Push Notification & In-App Notification to host
                    if host_id:
                        host_doc = db.collection('users').document(host_id).get()
                        if host_doc.exists:
                            fcm_token = host_doc.to_dict().get('fcmToken') or host_doc.to_dict().get('fcm_token')
                            if fcm_token:
                                message = messaging.Message(
                                    notification=messaging.Notification(
                                        title='Meeting Starting in 15 mins 🎥',
                                        body=f'Your meeting "{title}" begins shortly. Tap to enter the stage.'
                                    ),
                                    data={'roomId': room_id, 'action': 'open_room', 'type': 'meeting_reminder'},
                                    token=fcm_token,
                                )
                                try:
                                    response = messaging.send(message)
                                    logger.info(f"Successfully sent pre-meeting push to host {host_id}: {response}")
                                except Exception as e:
                                    logger.error(f"Error sending push to {host_id}: {e}")
                            
                            await send_in_app_notification(
                                user_id=host_id,
                                title='Meeting Starting in 15 mins 🎥',
                                body=f'"{title}" begins in 15 minutes. Tap to enter.',
                                notification_type='meeting_reminder',
                                action='open_room',
                                room_id=room_id
                            )
                    
                    # 2. Send Rich HTML Reminder Emails to attendees
                    for email in attendees:
                        send_email_reminder(email, title, room_id, sched_time)
                        
                    # Mark as notified
                    db.collection('meetings').document(doc_id).update({'notified': True})
                    logger.info(f"Meeting {doc_id} ('{title}') marked as notified")
                    
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
