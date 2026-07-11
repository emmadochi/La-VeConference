import logging
import os
import re
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
from livekit.api import AccessToken, VideoGrants
from livekit import api
import firebase_admin
from firebase_admin import credentials, auth

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

LIVEKIT_API_KEY = "devkey"
LIVEKIT_API_SECRET = "secret"

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
    
    lkapi = api.LiveKitAPI("http://localhost:7880", LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
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
    
    lkapi = api.LiveKitAPI("http://localhost:7880", LIVEKIT_API_KEY, LIVEKIT_API_SECRET)
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
            
    return {"livekit_url": "ws://192.168.100.57:7880"}
