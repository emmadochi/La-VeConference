import { getAuthToken } from "./auth.js";
import { BackgroundProcessor, supportsBackgroundProcessors } from "https://esm.sh/@livekit/track-processors@0.7.2";
import { KrispNoiseFilter } from "https://esm.sh/@livekit/krisp-noise-filter@0.1.3";

const { Room, RoomEvent, VideoPresences, Track, DataPacket_Kind } = LivekitClient;

const localVideo = document.getElementById('localVideo');
const videoGrid = document.getElementById('videoGrid');
const appLayout = document.getElementById('appLayout');
const joinScreen = document.getElementById('joinScreen');

// New UI Elements
const roomIdInput = document.getElementById('roomId');
const joinBtn = document.getElementById('joinBtn');
const newMeetingBtn = document.getElementById('newMeetingBtn');
const newMeetingDropdown = document.getElementById('newMeetingDropdown');
const instantMeetingBtn = document.getElementById('instantMeetingBtn');
const scheduleMeetingBtn = document.getElementById('scheduleMeetingBtn');
const scheduleModal = document.getElementById('scheduleModal');

const preJoinModal = document.getElementById('preJoinModal');
const userNameInput = document.getElementById('userName');
const preJoinSubmitBtn = document.getElementById('preJoinSubmitBtn');
const meetingInfo = document.getElementById('meetingInfo');

// Chat & Media Controls
const leaveCallBtn = document.getElementById('leaveCallBtn');
const chatInput = document.getElementById('chatInput');
const sendBtn = document.getElementById('sendBtn');
const chatMessages = document.getElementById('chatMessages');
const mediaControls = document.getElementById('mediaControls');
const toggleMicBtn = document.getElementById('toggleMicBtn');
const toggleVideoBtn = document.getElementById('toggleVideoBtn');
const flipCameraBtn = document.getElementById('flipCameraBtn');
const toggleScreenBtn = document.getElementById('toggleScreenBtn');
const toggleChatBtn = document.getElementById('toggleChatBtn');
const togglePeopleBtn = document.getElementById('togglePeopleBtn');
const toggleReactBtn = document.getElementById('toggleReactBtn');
const toggleEffectsBtn = document.getElementById('toggleEffectsBtn');
const effectsModal = document.getElementById('effectsModal');
const closeEffectsBtn = document.getElementById('closeEffectsBtn');
const effectsGrid = document.getElementById('effectsGrid');
const toggleNoiseBtn = document.getElementById('toggleNoiseBtn');
const toggleWhiteboardBtn = document.getElementById('toggleWhiteboardBtn');
const mainColumn = document.getElementById('mainColumn');
const whiteboardContainer = document.getElementById('whiteboardContainer');
const togglePollsBtn = document.getElementById('togglePollsBtn');
const pollQaSidebar = document.getElementById('pollQaSidebar');
const closePollQaBtn = document.getElementById('closePollQaBtn');
const qaBadge = document.getElementById('qaBadge');
const emojiPopover = document.getElementById('emojiPopover');
const toggleHandBtn = document.getElementById('toggleHandBtn');
const peopleSidebar = document.getElementById('peopleSidebar');
const closePeopleBtn = document.getElementById('closePeopleBtn');
const peopleList = document.getElementById('peopleList');

const raisedHands = new Set();
let isHandRaised = false;
let isWhiteboardActive = false;
let isPollQaOpen = false;

// Poll state
let activePoll = null;      // { question, options, votes: {optionIdx: count}, voters: Set }
let localVotedOption = null; // which option this user voted for
let qaQuestions = [];        // [{ id, author, text, upvotes, upvoters, answered, ts }]
let localQaUpvoted = new Set();
let newQaCount = 0;

let currentRoom = null;
let userName = "Anonymous";
let pendingRoomId = null;
let isMicEnabled = true;
let isVideoEnabled = true;
let isScreenSharing = false;
let currentFacingMode = 'user';
let audioContext = null;
let pinnedWrapperId = null;
let livekitUrlFallback = "ws://localhost:7880";
let isAdmin = false;

// Recording state
let mediaRecorder = null;
let recordedChunks = [];
let recordingAudioContext = null;
let recordingDestinationNode = null;
let audioSourceNodes = new Map();

let backgroundProcessor = null;
let krispFilter = null;
let isNoiseCancellationEnabled = false;

// --- NEW UI LOGIC ---

// URL Parsing
window.addEventListener('DOMContentLoaded', () => {
    // Setup QR Code
    const qrCodeImg = document.getElementById('qrCodeImg');
    const qrUrlText = document.getElementById('qrUrlText');
    if (qrCodeImg && qrUrlText) {
        const currentUrl = window.location.origin + window.location.pathname;
        qrCodeImg.src = `https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=${encodeURIComponent(currentUrl)}`;
        qrUrlText.textContent = currentUrl;
    }

    const params = new URLSearchParams(window.location.search);
    const roomParam = params.get('room');
    if (roomParam) {
        roomIdInput.value = roomParam;
        joinBtn.disabled = false;
        joinBtn.classList.add('active');
        // Auto-trigger join flow
        initiateJoinFlow(roomParam);
    }
});

// Join Button Enable/Disable
roomIdInput.addEventListener('input', (e) => {
    if (e.target.value.trim().length > 0) {
        joinBtn.disabled = false;
        joinBtn.classList.add('active');
    } else {
        joinBtn.disabled = true;
        joinBtn.classList.remove('active');
    }
});

// Dropdown Toggle
newMeetingBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    
    const user = window.firebaseAuth && window.firebaseAuth.currentUser;
    if (!user) {
        if (window.openAuthModal) {
            window.openAuthModal(true);
        } else {
            alert("Please log in to start a new meeting.");
        }
        return;
    }

    const isVisible = newMeetingDropdown.style.display === 'block';
    newMeetingDropdown.style.display = isVisible ? 'none' : 'block';
});
window.addEventListener('click', () => {
    newMeetingDropdown.style.display = 'none';
});

// Schedule button
scheduleMeetingBtn.addEventListener('click', () => {
    scheduleModal.style.display = 'flex';
});

// Instant Meeting
instantMeetingBtn.addEventListener('click', () => {
    const code = generateRoomCode();
    initiateJoinFlow(code);
});

// Join with Code
joinBtn.addEventListener('click', () => {
    const code = roomIdInput.value.trim();
    if (code) initiateJoinFlow(code);
});
roomIdInput.addEventListener('keypress', (e) => {
    if (e.key === 'Enter') {
        const code = roomIdInput.value.trim();
        if (code) initiateJoinFlow(code);
    }
});

function generateRoomCode() {
    const chars = 'abcdefghijklmnopqrstuvwxyz';
    let code = '';
    for(let i = 0; i < 10; i++) {
        if(i === 3 || i === 7) code += '-';
        else code += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return code;
}

// Pre-join flow
function initiateJoinFlow(roomId) {
    // If they passed a full link, extract just the room code
    try {
        const url = new URL(roomId);
        const urlRoom = url.searchParams.get('room');
        if (urlRoom) roomId = urlRoom;
    } catch(e) {}
    
    pendingRoomId = roomId;
    
    // Check if logged in. If logged in, we have a name.
    const user = window.firebaseAuth && window.firebaseAuth.currentUser;
    if (user && user.displayName) {
        userName = user.displayName;
        startCall(pendingRoomId);
    } else {
        // Ask for name
        preJoinModal.style.display = 'flex';
    }
}

preJoinSubmitBtn.addEventListener('click', () => {
    userName = userNameInput.value.trim() || "Anonymous";
    preJoinModal.style.display = 'none';
    startCall(pendingRoomId);
});

// --- EXISTING WEBRTC LOGIC ---

async function startCall(roomId) {
    try {
        joinScreen.style.display = 'none';
        appLayout.style.display = 'flex';
        mediaControls.style.display = 'flex';
        meetingInfo.innerHTML = `
            <div style="display: flex; align-items: center; gap: 10px; background: rgba(0,0,0,0.4); padding: 8px 16px; border-radius: 20px; border: 1px solid rgba(255,255,255,0.1);">
                <div class="meeting-code" style="margin: 0;">${roomId}</div>
                <button class="copy-link-btn" title="Copy Meeting Link" onclick="navigator.clipboard.writeText(window.location.origin + window.location.pathname + '?room=' + '${roomId}'); window.showToast('Meeting link copied!')" style="background: transparent; border: none; color: var(--text-muted); cursor: pointer; display: flex; align-items: center; padding: 4px; transition: color 0.2s;">
                    <span class="material-symbols-outlined" style="font-size: 20px;">content_copy</span>
                </button>
            </div>
        `;
        const peerId = Math.random().toString(36).substring(2, 10);
        
        // Fetch Token with optional Firebase ID Token
        const fbToken = await getAuthToken();
        const headers = {};
        if (fbToken) {
            headers['Authorization'] = `Bearer ${fbToken}`;
        }
        
        const response = await fetch(`/token/${roomId}/${peerId}?name=${encodeURIComponent(userName)}`, { headers });
        if (!response.ok) throw new Error("Failed to get token");
        const { token, is_admin } = await response.json();
        isAdmin = is_admin || false;
        
        const toggleRecordBtn = document.getElementById('toggleRecordBtn');
        if (isAdmin && toggleRecordBtn) {
            toggleRecordBtn.style.display = 'flex';
        }

        currentRoom = new Room({
            adaptiveStream: true,
            dynacast: true,
            videoCaptureDefaults: {
                facingMode: currentFacingMode
            }
        });

        currentRoom.on(RoomEvent.TrackSubscribed, (track, publication, participant) => {
            if (track.kind === 'video') {
                attachVideoTrack(track, participant, publication.source);
            } else if (track.kind === 'audio') {
                const audioElement = track.attach();
                document.body.appendChild(audioElement);
                setupSpeakingIndicator(track, participant.identity);
                
                // Route to recording if active
                if (recordingAudioContext && recordingDestinationNode && track.mediaStreamTrack) {
                    if (!audioSourceNodes.has(track.sid)) {
                        const source = recordingAudioContext.createMediaStreamSource(new MediaStream([track.mediaStreamTrack]));
                        source.connect(recordingDestinationNode);
                        audioSourceNodes.set(track.sid, source);
                    }
                }
            }
            renderParticipants();
        });

        currentRoom.on(RoomEvent.TrackUnsubscribed, (track, publication, participant) => {
            track.detach();
            if (track.kind === 'video') {
                const wrapper = document.getElementById(`wrapper-${participant.identity}-${publication.source}`);
                if (wrapper) wrapper.remove();
                updateVideoGridClass();
            }
        });

        currentRoom.on(RoomEvent.ParticipantConnected, (participant) => {
            appendSystemMessage(`${participant.name || 'Anonymous'} joined the room.`);
            renderParticipants();
        });

        currentRoom.on(RoomEvent.ParticipantDisconnected, (participant) => {
            appendSystemMessage(`${participant.name || 'Anonymous'} left the room.`);
            const wrappers = document.querySelectorAll(`[id^="wrapper-${participant.identity}-"]`);
            wrappers.forEach(w => w.remove());
            updateVideoGridClass();
            renderParticipants();
        });

        currentRoom.on(RoomEvent.DataReceived, (payload, participant, kind, topic) => {
            const strData = new TextDecoder().decode(payload);
            let data;
            try {
                data = JSON.parse(strData);
            } catch (e) {
                data = { type: 'chat', text: strData, sender: participant ? participant.name : 'Unknown' };
            }
            
            if (!data.type || data.type === 'chat') {
                appendMessage(data.sender || (participant ? participant.name : 'Unknown'), data.text, false);
                const chatSidebar = document.querySelector('.chat-sidebar');
                if (chatSidebar && !chatSidebar.classList.contains('show')) {
                    const badge = document.getElementById('chatBadge');
                    if (badge) badge.style.display = 'block';
                    playNotificationSound();
                }
            } else if (data.type === 'reaction') {
                showReaction(data.senderId || (participant ? participant.identity : null), data.emoji);
            } else if (data.type === 'raise_hand') {
                updateHandRaiseUI(data.senderId || (participant ? participant.identity : null), data.state);
            } else if (data.type === 'whiteboard_toggle') {
                if (data.state && !isWhiteboardActive) {
                    showToast(`${data.senderId || (participant ? participant.name : 'Someone')} opened the whiteboard.`);
                }
            } else if (data.type === 'poll_launch') {
                handlePollLaunch(data.poll);
            } else if (data.type === 'poll_vote') {
                handlePollVoteUpdate(data.optionIdx);
            } else if (data.type === 'poll_end') {
                handlePollEnd();
            } else if (data.type === 'qa_question') {
                handleQaNewQuestion(data.question);
            } else if (data.type === 'qa_upvote') {
                handleQaUpvote(data.questionId);
            } else if (data.type === 'qa_answered') {
                handleQaAnswered(data.questionId);
            }
        });

        currentRoom.on(RoomEvent.Disconnected, () => {
            console.log("Disconnected from room");
            leaveCall();
        });
        
        currentRoom.on(RoomEvent.LocalTrackPublished, (publication, participant) => {
            if (publication.track.kind === 'video' && publication.source === Track.Source.Camera) {
                publication.track.attach(localVideo);
            } else if (publication.track.kind === 'audio') {
                if (recordingAudioContext && recordingDestinationNode && publication.track.mediaStreamTrack) {
                    if (!audioSourceNodes.has(publication.trackSid)) {
                        const source = recordingAudioContext.createMediaStreamSource(new MediaStream([publication.track.mediaStreamTrack]));
                        source.connect(recordingDestinationNode);
                        audioSourceNodes.set(publication.trackSid, source);
                    }
                }
            }
        });

        currentRoom.on(RoomEvent.LocalTrackUnpublished, (publication, participant) => {
             if (publication.track && publication.track.kind === 'video' && publication.source === Track.Source.ScreenShare) {
                 isScreenSharing = false;
                 toggleScreenBtn.classList.remove('active');
                 toggleScreenBtn.querySelector('.material-symbols-outlined').textContent = 'present_to_all';
                 toggleScreenBtn.querySelector('.btn-text').textContent = 'Share';
             }
        });
        
        const wsProtocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
        let livekitHost = location.hostname;
        let livekitUrl = `${wsProtocol}//${livekitHost}:7880`;
        
        if (livekitHost.includes('loca.lt') || livekitHost.includes('trycloudflare.com')) {
            try {
                const configResponse = await fetch('/tunnel-config');
                const config = await configResponse.json();
                livekitUrl = config.livekit_url;
            } catch (e) {
                console.error("Failed to fetch tunnel config:", e);
            }
        } else if (livekitHost === 'localhost' || livekitHost === '127.0.0.1') {
            livekitUrl = "ws://127.0.0.1:7880";
        }
        
        await currentRoom.connect(livekitUrl, token);
        console.log("Connected to LiveKit!");

        await currentRoom.localParticipant.enableCameraAndMicrophone();
        
        try {
            if (supportsBackgroundProcessors()) {
                backgroundProcessor = BackgroundProcessor({ mode: 'disabled' });
                const videoTrack = currentRoom.localParticipant.getTrackPublication(Track.Source.Camera)?.videoTrack;
                if (videoTrack) {
                    await videoTrack.setProcessor(backgroundProcessor);
                }
            }
        } catch (e) {
            console.warn("Background processor initialization failed", e);
        }

        try {
            krispFilter = KrispNoiseFilter();
        } catch (e) {
            console.warn("Krisp noise filter initialization failed", e);
        }

        updateVideoGridClass();
        renderParticipants();
        
        chatInput.disabled = false;
        sendBtn.disabled = false;
        appendSystemMessage("You connected to the room.");
        
        // Update URL
        window.history.pushState({}, '', `?room=${roomId}`);

    } catch (err) {
        console.error("Connection error:", err);
        showToast("Could not connect: " + err.message, true);
        leaveCall();
    }
}

function leaveCall() {
    if (currentRoom) {
        currentRoom.disconnect();
        currentRoom = null;
    }

    appLayout.style.display = 'none';
    joinScreen.style.display = 'block';
    window.history.pushState({}, '', window.location.pathname);

    const wrappers = videoGrid.querySelectorAll('.video-wrapper:not(.local)');
    wrappers.forEach(w => w.remove());
    updateVideoGridClass();

    chatMessages.innerHTML = '<div class="chat-system">Messages can only be seen by people in the call and are deleted when the call ends.</div>';

    isMicEnabled = true;
    isVideoEnabled = true;
    isScreenSharing = false;

    toggleMicBtn.classList.add('active');
    toggleMicBtn.querySelector('.material-symbols-outlined').textContent = 'mic';
    toggleMicBtn.querySelector('.btn-text').textContent = 'Mute';
    toggleVideoBtn.classList.add('active');
    toggleVideoBtn.querySelector('.material-symbols-outlined').textContent = 'videocam';
    toggleVideoBtn.querySelector('.btn-text').textContent = 'Hide';
    toggleScreenBtn.classList.remove('active');
    toggleScreenBtn.querySelector('.material-symbols-outlined').textContent = 'present_to_all';
    toggleScreenBtn.querySelector('.btn-text').textContent = 'Share';
    
    if (backgroundProcessor) {
        backgroundProcessor.switchTo({ mode: 'disabled' }).catch(console.error);
    }
    if (toggleNoiseBtn) {
        isNoiseCancellationEnabled = false;
        toggleNoiseBtn.classList.remove('active');
    }

    if (toggleWhiteboardBtn) {
        isWhiteboardActive = false;
        toggleWhiteboardBtn.classList.remove('active');
        mainColumn.classList.remove('with-whiteboard');
        whiteboardContainer.classList.remove('active');
        whiteboardContainer.innerHTML = '';
    }

    // Reset Polls & Q&A
    activePoll = null;
    localVotedOption = null;
    qaQuestions = [];
    localQaUpvoted = new Set();
    newQaCount = 0;
    if (pollQaSidebar) {
        pollQaSidebar.classList.remove('open');
        isPollQaOpen = false;
    }
    if (togglePollsBtn) togglePollsBtn.classList.remove('active');
    if (qaBadge) qaBadge.style.display = 'none';
    renderPollsUI();
    renderQaUI();

    const toggleRecordBtn = document.getElementById('toggleRecordBtn');
    if (toggleRecordBtn) toggleRecordBtn.style.display = 'none';
    stopRecording();

    chatInput.disabled = true;
    sendBtn.disabled = true;
}

leaveCallBtn.addEventListener('click', leaveCall);

// --- Media Controls ---
toggleMicBtn.addEventListener('click', async () => {
    if (!currentRoom) return;
    isMicEnabled = !isMicEnabled;
    await currentRoom.localParticipant.setMicrophoneEnabled(isMicEnabled);
    
    toggleMicBtn.classList.toggle('active', isMicEnabled);
    const icon = toggleMicBtn.querySelector('.material-symbols-outlined');
    const text = toggleMicBtn.querySelector('.btn-text');
    icon.textContent = isMicEnabled ? 'mic' : 'mic_off';
    text.textContent = isMicEnabled ? 'Mute' : 'Unmute';
});

toggleVideoBtn.addEventListener('click', async () => {
    if (!currentRoom) return;
    isVideoEnabled = !isVideoEnabled;
    await currentRoom.localParticipant.setCameraEnabled(isVideoEnabled);
    
    toggleVideoBtn.classList.toggle('active', isVideoEnabled);
    const icon = toggleVideoBtn.querySelector('.material-symbols-outlined');
    const text = toggleVideoBtn.querySelector('.btn-text');
    icon.textContent = isVideoEnabled ? 'videocam' : 'videocam_off';
    text.textContent = isVideoEnabled ? 'Hide' : 'Show';
});

if (flipCameraBtn) {
    if (!('ontouchstart' in window) && navigator.maxTouchPoints === 0) {
        flipCameraBtn.style.display = 'none';
    }
    flipCameraBtn.addEventListener('click', async () => {
        if (!currentRoom) return;
        currentFacingMode = currentFacingMode === 'user' ? 'environment' : 'user';
        await currentRoom.localParticipant.setCameraEnabled(false);
        await currentRoom.localParticipant.setCameraEnabled(true, { facingMode: currentFacingMode });
    });
}

const isMobileDevice = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent) || (navigator.maxTouchPoints && navigator.maxTouchPoints > 2);

if (isMobileDevice && toggleScreenBtn) {
    toggleScreenBtn.style.display = 'none';
}

toggleScreenBtn.addEventListener('click', async () => {
    if (!currentRoom) return;
    if (!isScreenSharing) {
        try {
            await currentRoom.localParticipant.setScreenShareEnabled(true);
            isScreenSharing = true;
            toggleScreenBtn.classList.add('active');
            toggleScreenBtn.querySelector('.material-symbols-outlined').textContent = 'cancel_presentation';
            toggleScreenBtn.querySelector('.btn-text').textContent = 'Stop';
        } catch (err) {
            console.error("Error sharing screen:", err);
            showToast("Could not share screen: " + (err.message || "Not supported on this device."), true);
        }
    } else {
        await currentRoom.localParticipant.setScreenShareEnabled(false);
        isScreenSharing = false;
        toggleScreenBtn.classList.remove('active');
        toggleScreenBtn.querySelector('.material-symbols-outlined').textContent = 'present_to_all';
        toggleScreenBtn.querySelector('.btn-text').textContent = 'Share';
    }
});

const toggleRecordBtn = document.getElementById('toggleRecordBtn');
if (toggleRecordBtn) {
    toggleRecordBtn.addEventListener('click', async () => {
        if (mediaRecorder && mediaRecorder.state !== 'inactive') {
            stopRecording();
            saveRecording();
        } else {
            await startRecording();
        }
    });
}

// Chat sidebar logic
if (toggleChatBtn) {
    const chatSidebar = document.querySelector('.chat-sidebar:not(.people-sidebar)');
    const closeChatBtn = document.getElementById('closeChatBtn');
    toggleChatBtn.addEventListener('click', () => {
        if (chatSidebar) {
            if (peopleSidebar && peopleSidebar.classList.contains('show')) {
                peopleSidebar.classList.remove('show');
                togglePeopleBtn.classList.remove('active');
            }
            chatSidebar.classList.toggle('show');
            const isOpen = chatSidebar.classList.contains('show');
            toggleChatBtn.classList.toggle('active', isOpen);
            if (isOpen) {
                const badge = document.getElementById('chatBadge');
                if (badge) badge.style.display = 'none';
            }
        }
    });
    if (closeChatBtn) {
        closeChatBtn.addEventListener('click', () => {
            chatSidebar.classList.remove('show');
            toggleChatBtn.classList.remove('active');
        });
    }
}

// People sidebar logic
if (togglePeopleBtn) {
    const chatSidebar = document.querySelector('.chat-sidebar:not(.people-sidebar)');
    togglePeopleBtn.addEventListener('click', () => {
        if (peopleSidebar) {
            if (chatSidebar && chatSidebar.classList.contains('show')) {
                chatSidebar.classList.remove('show');
                toggleChatBtn.classList.remove('active');
            }
            peopleSidebar.classList.toggle('show');
            togglePeopleBtn.classList.toggle('active', peopleSidebar.classList.contains('show'));
        }
    });
    if (closePeopleBtn) {
        closePeopleBtn.addEventListener('click', () => {
            peopleSidebar.classList.remove('show');
            togglePeopleBtn.classList.remove('active');
        });
    }
}

// Sending messages
function sendMessage() {
    const text = chatInput.value.trim();
    if (text && currentRoom && currentRoom.state === 'connected') {
        const payload = JSON.stringify({ type: 'chat', sender: userName, text: text });
        const data = new TextEncoder().encode(payload);
        currentRoom.localParticipant.publishData(data, { reliable: true });
        appendMessage(userName + " (You)", text, true);
        chatInput.value = '';
    }
}
sendBtn.addEventListener('click', sendMessage);
chatInput.addEventListener('keypress', (e) => {
    if (e.key === 'Enter') sendMessage();
});

function appendMessage(sender, text, isSelf) {
    const msgDiv = document.createElement('div');
    msgDiv.className = `chat-message ${isSelf ? 'self' : ''}`;
    const senderDiv = document.createElement('div');
    senderDiv.className = 'sender';
    senderDiv.textContent = sender;
    const textDiv = document.createElement('div');
    textDiv.className = 'text';
    textDiv.textContent = text;
    msgDiv.appendChild(senderDiv);
    msgDiv.appendChild(textDiv);
    chatMessages.appendChild(msgDiv);
    chatMessages.scrollTop = chatMessages.scrollHeight;
}

function appendSystemMessage(text) {
    const msgDiv = document.createElement('div');
    msgDiv.className = 'chat-system';
    msgDiv.textContent = text;
    chatMessages.appendChild(msgDiv);
    chatMessages.scrollTop = chatMessages.scrollHeight;
}

// --- Utilities ---
function renderParticipants() {
    if (!currentRoom || !peopleList) return;
    peopleList.innerHTML = '';
    
    // Add local participant
    const local = currentRoom.localParticipant;
    if (local) peopleList.appendChild(createParticipantElement(local, true));
    
    // Add remote participants
    currentRoom.remoteParticipants.forEach((p) => {
        peopleList.appendChild(createParticipantElement(p, false));
    });
}

function createParticipantElement(participant, isLocal) {
    const div = document.createElement('div');
    div.className = 'participant-item';
    
    const name = participant.name || participant.identity;
    const initial = name.charAt(0).toUpperCase();
    
    let infoHtml = `
        <div class="participant-info">
            <div class="participant-avatar">${initial}</div>
            <div class="participant-name">${name} ${isLocal ? '(You)' : ''} ${raisedHands.has(participant.identity) ? '✋' : ''}</div>
        </div>
    `;
    
    let actionsHtml = '';
    if (isAdmin && !isLocal) {
        let audioTrackSid = null;
        participant.audioTrackPublications.forEach(pub => {
            if (pub.trackSid) audioTrackSid = pub.trackSid;
        });
        
        actionsHtml = `<div class="participant-actions">`;
        if (audioTrackSid) {
            actionsHtml += `<button class="action-btn" onclick="muteParticipant('${participant.identity}', '${audioTrackSid}')" title="Mute"><span class="material-symbols-outlined">mic_off</span></button>`;
        }
        actionsHtml += `<button class="action-btn kick-btn" onclick="kickParticipant('${participant.identity}')" title="Remove"><span class="material-symbols-outlined">person_remove</span></button>`;
        actionsHtml += `</div>`;
    }
    
    div.innerHTML = infoHtml + actionsHtml;
    return div;
}

window.muteParticipant = async (identity, trackSid) => {
    if (!isAdmin || !currentRoom) return;
    try {
        const fbToken = await getAuthToken();
        const res = await fetch('/api/mute', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${fbToken}` },
            body: JSON.stringify({ room_id: currentRoom.name, identity, track_sid: trackSid })
        });
        if (!res.ok) throw new Error("Failed to mute");
        showToast("Participant muted");
    } catch(err) {
        showToast("Error muting participant", true);
    }
};

window.kickParticipant = async (identity) => {
    if (!isAdmin || !currentRoom) return;
    try {
        const fbToken = await getAuthToken();
        const res = await fetch('/api/kick', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${fbToken}` },
            body: JSON.stringify({ room_id: currentRoom.name, identity })
        });
        if (!res.ok) throw new Error("Failed to remove");
        showToast("Participant removed");
    } catch(err) {
        showToast("Error removing participant", true);
    }
};

function showToast(message, isError = false) {
    const toast = document.createElement('div');
    toast.style.position = 'fixed';
    toast.style.bottom = '120px';
    toast.style.left = '50%';
    toast.style.transform = 'translateX(-50%)';
    toast.style.backgroundColor = isError ? '#ef4444' : '#22c55e';
    toast.style.color = 'white';
    toast.style.padding = '12px 24px';
    toast.style.borderRadius = '12px';
    toast.style.zIndex = '9999';
    toast.style.fontWeight = '600';
    toast.style.boxShadow = '0 10px 25px rgba(0,0,0,0.5)';
    toast.style.textAlign = 'center';
    toast.style.maxWidth = '90%';
    toast.textContent = message;
    
    document.body.appendChild(toast);
    
    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transition = 'opacity 0.5s ease-out';
        setTimeout(() => toast.remove(), 500);
    }, 3500);
}
window.showToast = showToast;
function attachVideoTrack(track, participant, source) {
    let wrapper = document.getElementById(`wrapper-${participant.identity}-${source}`);
    if (!wrapper) {
        wrapper = document.createElement('div');
        wrapper.className = 'video-wrapper';
        wrapper.id = `wrapper-${participant.identity}-${source}`;
        
        const label = document.createElement('span');
        label.className = 'label';
        const srcText = source === Track.Source.ScreenShare ? "'s Screen" : "";
        label.textContent = (participant.name || participant.identity) + srcText;
        
        const pinBtn = document.createElement('button');
        pinBtn.className = 'pin-overlay-btn';
        pinBtn.title = 'Spotlight Video';
        pinBtn.innerHTML = '<span class="material-symbols-outlined">push_pin</span>';
        pinBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            togglePin(wrapper.id);
        });

        const pipBtn = document.createElement('button');
        pipBtn.className = 'pip-overlay-btn';
        pipBtn.title = 'Picture in Picture';
        pipBtn.innerHTML = '<span class="material-symbols-outlined">picture_in_picture_alt</span>';
        pipBtn.addEventListener('click', async (e) => {
            e.stopPropagation();
            const videoElement = wrapper.querySelector('video');
            if (videoElement) {
                if (document.pictureInPictureElement) {
                    await document.exitPictureInPicture();
                } else if (videoElement.requestPictureInPicture) {
                    await videoElement.requestPictureInPicture();
                }
            }
        });
        
        wrapper.addEventListener('dblclick', () => {
            togglePin(wrapper.id);
        });
        
        wrapper.appendChild(label);
        wrapper.appendChild(pinBtn);
        wrapper.appendChild(pipBtn);
        videoGrid.appendChild(wrapper);
    }
    
    const videoElement = track.attach();
    if (source === Track.Source.ScreenShare) {
        videoElement.style.objectFit = 'contain';
        videoElement.style.backgroundColor = '#000';
    }
    wrapper.insertBefore(videoElement, wrapper.firstChild);
    updateVideoGridClass();
}

function setupSpeakingIndicator(audioTrack, participantIdentity) {
    if (!audioContext) audioContext = new (window.AudioContext || window.webkitAudioContext)();
    try {
        const mediaStreamTrack = audioTrack.mediaStreamTrack;
        if (!mediaStreamTrack) return;
        
        const source = audioContext.createMediaStreamSource(new MediaStream([mediaStreamTrack]));
        const analyser = audioContext.createAnalyser();
        analyser.fftSize = 256;
        source.connect(analyser);
        const dataArray = new Uint8Array(analyser.frequencyBinCount);

        function checkVolume() {
            if (!currentRoom) return; 
            requestAnimationFrame(checkVolume);
            const wrapper = document.getElementById(`wrapper-${participantIdentity}-${Track.Source.Camera}`);
            if (!wrapper) return;
            analyser.getByteFrequencyData(dataArray);
            let sum = 0;
            for (let i = 0; i < dataArray.length; i++) sum += dataArray[i];
            const average = sum / dataArray.length;
            if (average > 15) wrapper.classList.add('speaking');
            else wrapper.classList.remove('speaking');
        }
        checkVolume();
    } catch (e) {
        console.warn("Could not setup speaking indicator", e);
    }
}

function updateVideoGridClass() {
    if (!videoGrid) return;
    const count = videoGrid.querySelectorAll('.video-wrapper').length;
    const classesToRemove = Array.from(videoGrid.classList).filter(c => c.startsWith('grid-count-'));
    classesToRemove.forEach(c => videoGrid.classList.remove(c));
    videoGrid.classList.add(`grid-count-${count}`);
}

function togglePin(wrapperId) {
    const grid = document.getElementById('videoGrid');
    if (pinnedWrapperId === wrapperId) {
        const current = document.getElementById(pinnedWrapperId);
        if (current) current.classList.remove('pinned');
        grid.classList.remove('has-pinned');
        pinnedWrapperId = null;
        return;
    }
    if (pinnedWrapperId) {
        const prev = document.getElementById(pinnedWrapperId);
        if (prev) prev.classList.remove('pinned');
    }
    const newPinned = document.getElementById(wrapperId);
    if (newPinned) {
        newPinned.classList.add('pinned');
        grid.classList.add('has-pinned');
        pinnedWrapperId = wrapperId;
    }
}

const localWrapper = document.getElementById('wrapper-local-camera');
if (localWrapper) {
    localWrapper.addEventListener('dblclick', () => togglePin(localWrapper.id));
    const pinBtn = localWrapper.querySelector('.pin-overlay-btn');
    if (pinBtn) {
        pinBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            togglePin(localWrapper.id);
        });
    }
}

async function startRecording() {
    try {
        recordingAudioContext = new (window.AudioContext || window.webkitAudioContext)();
        recordingDestinationNode = recordingAudioContext.createMediaStreamDestination();
        audioSourceNodes.clear();
        recordedChunks = [];
        
        const connectTrack = (trackSid, mediaStreamTrack) => {
            if (mediaStreamTrack && !audioSourceNodes.has(trackSid)) {
                const source = recordingAudioContext.createMediaStreamSource(new MediaStream([mediaStreamTrack]));
                source.connect(recordingDestinationNode);
                audioSourceNodes.set(trackSid, source);
            }
        };

        if (currentRoom.localParticipant) {
            currentRoom.localParticipant.audioTrackPublications.forEach(pub => {
                if (pub.track && pub.track.mediaStreamTrack) connectTrack(pub.trackSid, pub.track.mediaStreamTrack);
            });
        }
        
        currentRoom.remoteParticipants.forEach(p => {
            p.audioTrackPublications.forEach(pub => {
                if (pub.track && pub.track.mediaStreamTrack) connectTrack(pub.trackSid, pub.track.mediaStreamTrack);
            });
        });
        
        const options = { mimeType: 'audio/webm' };
        mediaRecorder = new MediaRecorder(recordingDestinationNode.stream, options);
        mediaRecorder.ondataavailable = (e) => {
            if (e.data.size > 0) recordedChunks.push(e.data);
        };
        mediaRecorder.start(1000);
        
        if (toggleRecordBtn) {
            toggleRecordBtn.classList.add('recording');
            toggleRecordBtn.querySelector('.btn-text').textContent = 'Stop Rec';
        }
        showToast("Recording started");
    } catch(err) {
        console.error(err);
        showToast("Failed to start recording", true);
    }
}

function stopRecording() {
    if (mediaRecorder && mediaRecorder.state !== 'inactive') {
        mediaRecorder.stop();
    }
    mediaRecorder = null;
    
    if (recordingAudioContext) {
        recordingAudioContext.close();
        recordingAudioContext = null;
    }
    recordingDestinationNode = null;
    audioSourceNodes.clear();
    
    if (toggleRecordBtn) {
        toggleRecordBtn.classList.remove('recording');
        toggleRecordBtn.querySelector('.btn-text').textContent = 'Record';
    }
}

function saveRecording() {
    if (recordedChunks.length === 0) return;
    const blob = new Blob(recordedChunks, { type: 'audio/webm' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    document.body.appendChild(a);
    a.style.display = 'none';
    a.href = url;
    a.download = `Meeting_Recording_${new Date().getTime()}.webm`;
    a.click();
    URL.revokeObjectURL(url);
    showToast("Recording saved!");
    recordedChunks = [];
}

function playNotificationSound() {} // stub

// --- Theme Toggling ---
const themeToggleBtn = document.getElementById('themeToggleBtn');
const themeIcon = document.getElementById('themeIcon');

function setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
    if (themeIcon) {
        themeIcon.textContent = theme === 'dark' ? 'light_mode' : 'dark_mode';
    }
}

// Initialize theme
const savedTheme = localStorage.getItem('theme') || 'dark';
setTheme(savedTheme);

if (themeToggleBtn) {
    themeToggleBtn.addEventListener('click', () => {
        const currentTheme = document.documentElement.getAttribute('data-theme');
        const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
        setTheme(newTheme);
    });
}

// --- Interactive Features ---
if (toggleReactBtn) {
    toggleReactBtn.addEventListener('click', () => {
        emojiPopover.style.display = emojiPopover.style.display === 'none' ? 'flex' : 'none';
    });
}

document.querySelectorAll('.emoji-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
        const emoji = e.target.textContent;
        emojiPopover.style.display = 'none';
        if (currentRoom && currentRoom.state === 'connected') {
            const payload = JSON.stringify({ type: 'reaction', emoji: emoji, senderId: currentRoom.localParticipant.identity });
            const data = new TextEncoder().encode(payload);
            currentRoom.localParticipant.publishData(data, { reliable: true });
            showReaction(currentRoom.localParticipant.identity, emoji);
        }
    });
});

if (toggleHandBtn) {
    toggleHandBtn.addEventListener('click', () => {
        if (!currentRoom || currentRoom.state !== 'connected') return;
        isHandRaised = !isHandRaised;
        toggleHandBtn.classList.toggle('hand-raised', isHandRaised);
        
        const payload = JSON.stringify({ type: 'raise_hand', state: isHandRaised, senderId: currentRoom.localParticipant.identity });
        const data = new TextEncoder().encode(payload);
        currentRoom.localParticipant.publishData(data, { reliable: true });
        
        updateHandRaiseUI(currentRoom.localParticipant.identity, isHandRaised);
    });
}

function showReaction(identity, emoji) {
    if (!identity) return;
    const wrappers = document.querySelectorAll(`[id^="wrapper-${identity}-"]`);
    if (wrappers.length === 0) return;
    
    // Use the first wrapper (camera usually)
    const wrapper = wrappers[0];
    const emojiEl = document.createElement('div');
    emojiEl.className = 'floating-emoji';
    emojiEl.textContent = emoji;
    wrapper.appendChild(emojiEl);
    
    setTimeout(() => {
        if (emojiEl.parentNode) emojiEl.remove();
    }, 2500);
}

function updateHandRaiseUI(identity, isRaised) {
    if (!identity) return;
    
    if (isRaised) {
        raisedHands.add(identity);
    } else {
        raisedHands.delete(identity);
    }
    
    const wrappers = document.querySelectorAll(`[id^="wrapper-${identity}-"]`);
    wrappers.forEach(wrapper => {
        let badge = wrapper.querySelector('.hand-badge');
        if (isRaised && !badge) {
            badge = document.createElement('div');
            badge.className = 'hand-badge';
            badge.textContent = '✋';
            wrapper.appendChild(badge);
        } else if (!isRaised && badge) {
            badge.remove();
        }
    });
    
    renderParticipants();
}

// --- AI EFFECTS ---
if (toggleEffectsBtn) {
    toggleEffectsBtn.addEventListener('click', () => {
        effectsModal.style.display = 'flex';
    });
    closeEffectsBtn.addEventListener('click', () => {
        effectsModal.style.display = 'none';
    });
}

if (effectsGrid) {
    const options = effectsGrid.querySelectorAll('.effect-option');
    options.forEach(option => {
        option.addEventListener('click', async () => {
            if (!backgroundProcessor || !currentRoom) {
                showToast("Background effects not supported on this device.", true);
                return;
            }
            
            options.forEach(o => o.classList.remove('active'));
            option.classList.add('active');
            
            const effect = option.getAttribute('data-effect');
            
            try {
                if (effect === 'none') {
                    await backgroundProcessor.switchTo({ mode: 'disabled' });
                } else if (effect === 'blur') {
                    await backgroundProcessor.switchTo({ mode: 'background-blur', blurRadius: 15 });
                } else {
                    const imagePath = `/static/assets/${effect}.png`;
                    await backgroundProcessor.switchTo({ mode: 'virtual-background', imagePath: imagePath });
                }
            } catch(e) {
                console.error("Error switching background effect", e);
                showToast("Failed to apply effect. Try again.", true);
            }
        });
    });
}

if (toggleNoiseBtn) {
    toggleNoiseBtn.addEventListener('click', async () => {
        if (!currentRoom || !krispFilter) {
            showToast("Noise cancellation not available.", true);
            return;
        }
        
        const audioTrack = currentRoom.localParticipant.getTrackPublication(Track.Source.Microphone)?.audioTrack;
        if (!audioTrack) return;
        
        isNoiseCancellationEnabled = !isNoiseCancellationEnabled;
        toggleNoiseBtn.classList.toggle('active', isNoiseCancellationEnabled);
        
        try {
            if (isNoiseCancellationEnabled) {
                await audioTrack.setProcessor(krispFilter);
                showToast("AI Noise Cancellation Enabled");
            } else {
                await audioTrack.stopProcessor();
                showToast("AI Noise Cancellation Disabled");
            }
        } catch(e) {
            console.error("Error toggling noise filter", e);
            isNoiseCancellationEnabled = !isNoiseCancellationEnabled;
            toggleNoiseBtn.classList.toggle('active', isNoiseCancellationEnabled);
            showToast("Failed to toggle noise cancellation.", true);
        }
    });
}

// --- WHITEBOARD ---
if (toggleWhiteboardBtn) {
    toggleWhiteboardBtn.addEventListener('click', () => {
        if (!currentRoom || currentRoom.state !== 'connected') return;
        
        isWhiteboardActive = !isWhiteboardActive;
        toggleWhiteboardBtn.classList.toggle('active', isWhiteboardActive);
        
        if (isWhiteboardActive) {
            mainColumn.classList.add('with-whiteboard');
            whiteboardContainer.classList.add('active');
            
            if (!whiteboardContainer.querySelector('iframe')) {
                const iframe = document.createElement('iframe');
                iframe.src = `https://wbo.ophir.dev/boards/lavie-${currentRoom.name}`;
                whiteboardContainer.appendChild(iframe);
            }
            
            const payload = JSON.stringify({ type: 'whiteboard_toggle', state: true, senderId: currentRoom.localParticipant.identity });
            const data = new TextEncoder().encode(payload);
            currentRoom.localParticipant.publishData(data, { reliable: true });
            
        } else {
            mainColumn.classList.remove('with-whiteboard');
            whiteboardContainer.classList.remove('active');
            
            const payload = JSON.stringify({ type: 'whiteboard_toggle', state: false, senderId: currentRoom.localParticipant.identity });
            const data = new TextEncoder().encode(payload);
            currentRoom.localParticipant.publishData(data, { reliable: true });
        }
    });
}

// ==========================================
// LIVE POLLS & Q&A
// ==========================================

function broadcast(payload) {
    if (!currentRoom || currentRoom.state !== 'connected') return;
    const data = new TextEncoder().encode(JSON.stringify(payload));
    currentRoom.localParticipant.publishData(data, { reliable: true });
}

// --- Sidebar Toggle ---
if (togglePollsBtn) {
    togglePollsBtn.addEventListener('click', () => {
        isPollQaOpen = !isPollQaOpen;
        pollQaSidebar.classList.toggle('open', isPollQaOpen);
        togglePollsBtn.classList.toggle('active', isPollQaOpen);
        if (isPollQaOpen) {
            newQaCount = 0;
            if (qaBadge) qaBadge.style.display = 'none';
        }
    });
}

if (closePollQaBtn) {
    closePollQaBtn.addEventListener('click', () => {
        isPollQaOpen = false;
        pollQaSidebar.classList.remove('open');
        togglePollsBtn.classList.remove('active');
    });
}

// --- Tab switching ---
document.querySelectorAll('.pq-tab').forEach(tab => {
    tab.addEventListener('click', () => {
        document.querySelectorAll('.pq-tab').forEach(t => t.classList.remove('active'));
        tab.classList.add('active');
        const which = tab.getAttribute('data-tab');
        document.getElementById('tabContentPolls').style.display = which === 'polls' ? 'flex' : 'none';
        document.getElementById('tabContentQA').style.display = which === 'qa' ? 'flex' : 'none';
    });
});

// ---- POLLS ----

function renderPollsUI() {
    const createSection = document.getElementById('pollCreateSection');
    const activeSection = document.getElementById('pollActiveSection');
    const emptyState = document.getElementById('pollEmptyState');

    if (!createSection || !activeSection || !emptyState) return;

    if (activePoll) {
        createSection.style.display = 'none';
        emptyState.style.display = 'none';
        activeSection.style.display = 'flex';
        activeSection.style.flexDirection = 'column';
        activeSection.style.gap = '10px';

        document.getElementById('activePollQuestion').textContent = activePoll.question;

        const endBtn = document.getElementById('endPollBtn');
        if (endBtn) endBtn.style.display = isAdmin ? 'block' : 'none';

        const totalVotes = Object.values(activePoll.votes).reduce((s, v) => s + v, 0);

        const optionsDisplay = document.getElementById('pollOptionsDisplay');
        optionsDisplay.innerHTML = '';

        activePoll.options.forEach((opt, idx) => {
            const votes = activePoll.votes[idx] || 0;
            const pct = totalVotes ? Math.round((votes / totalVotes) * 100) : 0;
            const btn = document.createElement('button');
            btn.className = 'poll-vote-btn' + (localVotedOption === idx ? ' voted-for' : '') + (localVotedOption !== null ? ' disabled' : '');
            btn.style.setProperty('--pct', pct + '%');

            btn.innerHTML = `<span>${opt}</span>
                <span>
                    <strong>${pct}%</strong>
                    <span class="poll-votes-count">(${votes})</span>
                </span>`;

            if (localVotedOption === null) {
                btn.addEventListener('click', () => castVote(idx));
            }
            optionsDisplay.appendChild(btn);
        });

        document.getElementById('pollResultsBar').innerHTML = `<p class="poll-total-votes">${totalVotes} vote${totalVotes !== 1 ? 's' : ''} total</p>`;
    } else {
        activeSection.style.display = 'none';
        emptyState.style.display = 'flex';
        if (createSection) {
            createSection.style.display = isAdmin ? 'flex' : 'none';
            createSection.style.flexDirection = 'column';
        }
    }
}

function castVote(optionIdx) {
    if (!currentRoom || localVotedOption !== null || !activePoll) return;
    localVotedOption = optionIdx;
    activePoll.votes[optionIdx] = (activePoll.votes[optionIdx] || 0) + 1;
    renderPollsUI();
    broadcast({ type: 'poll_vote', optionIdx });
}

function handlePollLaunch(poll) {
    activePoll = { ...poll, votes: {} };
    poll.options.forEach((_, i) => { activePoll.votes[i] = 0; });
    localVotedOption = null;
    renderPollsUI();
    showToast('📊 New poll launched!');
    if (!isPollQaOpen) {
        if (qaBadge) qaBadge.style.display = 'block';
    }
}

function handlePollVoteUpdate(optionIdx) {
    if (!activePoll) return;
    activePoll.votes[optionIdx] = (activePoll.votes[optionIdx] || 0) + 1;
    renderPollsUI();
}

function handlePollEnd() {
    if (!activePoll) return;
    showToast('📊 Poll ended.');
    activePoll = null;
    localVotedOption = null;
    renderPollsUI();
}

// Host: Add poll option
const addPollOptionBtn = document.getElementById('addPollOptionBtn');
if (addPollOptionBtn) {
    addPollOptionBtn.addEventListener('click', () => {
        const container = document.getElementById('pollOptionsContainer');
        const count = container.querySelectorAll('.poll-option-input').length + 1;
        if (count > 6) { showToast('Max 6 options allowed.', true); return; }
        const inp = document.createElement('input');
        inp.type = 'text';
        inp.className = 'modal-input poll-option-input';
        inp.placeholder = `Option ${count}`;
        container.appendChild(inp);
    });
}

// Host: Launch poll
const launchPollBtn = document.getElementById('launchPollBtn');
if (launchPollBtn) {
    launchPollBtn.addEventListener('click', () => {
        if (!currentRoom || currentRoom.state !== 'connected') return;
        const question = document.getElementById('pollQuestionInput').value.trim();
        const optInputs = document.querySelectorAll('.poll-option-input');
        const options = Array.from(optInputs).map(i => i.value.trim()).filter(Boolean);

        if (!question) { showToast('Please enter a question.', true); return; }
        if (options.length < 2) { showToast('Please add at least 2 options.', true); return; }

        const poll = { question, options };
        handlePollLaunch(poll);
        broadcast({ type: 'poll_launch', poll });

        // Reset form
        document.getElementById('pollQuestionInput').value = '';
        optInputs.forEach((inp, i) => { inp.value = ''; if (i >= 2) inp.remove(); });
    });
}

// Host: End poll
const endPollBtn = document.getElementById('endPollBtn');
if (endPollBtn) {
    endPollBtn.addEventListener('click', () => {
        handlePollEnd();
        broadcast({ type: 'poll_end' });
    });
}

// ---- Q&A ----

function renderQaUI() {
    const list = document.getElementById('qaQuestionsList');
    const emptyState = document.getElementById('qaEmptyState');
    if (!list) return;

    // Remove old question cards (keep empty state)
    list.querySelectorAll('.qa-question-card').forEach(c => c.remove());

    if (qaQuestions.length === 0) {
        if (emptyState) emptyState.style.display = 'flex';
        return;
    }
    if (emptyState) emptyState.style.display = 'none';

    // Sort: unanswered first, then by upvotes desc
    const sorted = [...qaQuestions].sort((a, b) => {
        if (a.answered !== b.answered) return a.answered ? 1 : -1;
        return b.upvotes - a.upvotes;
    });

    sorted.forEach(q => {
        const card = document.createElement('div');
        card.className = 'qa-question-card';
        card.id = `qa-${q.id}`;

        const timeStr = new Date(q.ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        const hasVoted = localQaUpvoted.has(q.id);

        card.innerHTML = `
            <div class="qa-question-meta">
                <span class="qa-question-author">${q.author}</span>
                <span class="qa-question-time">${timeStr}</span>
            </div>
            <p class="qa-question-text">${q.text}</p>
            <div class="qa-question-actions">
                <button class="qa-upvote-btn${hasVoted ? ' voted' : ''}" data-id="${q.id}">
                    👍 ${q.upvotes}
                </button>
                ${q.answered ? '<span class="qa-answered-badge">✓ Answered</span>' : ''}
                ${isAdmin && !q.answered ? `<button class="qa-answer-btn" data-id="${q.id}">Mark Answered</button>` : ''}
            </div>
        `;

        // Upvote
        card.querySelector('.qa-upvote-btn').addEventListener('click', () => {
            if (localQaUpvoted.has(q.id)) return;
            localQaUpvoted.add(q.id);
            const qObj = qaQuestions.find(x => x.id === q.id);
            if (qObj) qObj.upvotes++;
            renderQaUI();
            broadcast({ type: 'qa_upvote', questionId: q.id });
        });

        // Admin: Mark as answered
        const ansBtn = card.querySelector('.qa-answer-btn');
        if (ansBtn) {
            ansBtn.addEventListener('click', () => {
                handleQaAnswered(q.id);
                broadcast({ type: 'qa_answered', questionId: q.id });
            });
        }

        list.appendChild(card);
    });

    list.scrollTop = list.scrollHeight;
}

function handleQaNewQuestion(question) {
    qaQuestions.push(question);
    renderQaUI();
    if (!isPollQaOpen) {
        newQaCount++;
        if (qaBadge) qaBadge.style.display = 'block';
        showToast(`❓ New question from ${question.author}`);
    }
}

function handleQaUpvote(questionId) {
    const q = qaQuestions.find(x => x.id === questionId);
    if (q) {
        q.upvotes++;
        renderQaUI();
    }
}

function handleQaAnswered(questionId) {
    const q = qaQuestions.find(x => x.id === questionId);
    if (q) {
        q.answered = true;
        renderQaUI();
    }
}

// Submit a question
const submitQaBtn = document.getElementById('submitQaBtn');
const qaQuestionInput = document.getElementById('qaQuestionInput');
if (submitQaBtn && qaQuestionInput) {
    submitQaBtn.addEventListener('click', () => {
        if (!currentRoom || currentRoom.state !== 'connected') return;
        const text = qaQuestionInput.value.trim();
        if (!text) return;

        const question = {
            id: Date.now().toString(36) + Math.random().toString(36).slice(2),
            author: userName,
            text,
            upvotes: 0,
            answered: false,
            ts: Date.now()
        };

        handleQaNewQuestion(question);
        broadcast({ type: 'qa_question', question });
        qaQuestionInput.value = '';
    });

    qaQuestionInput.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') submitQaBtn.click();
    });
}

