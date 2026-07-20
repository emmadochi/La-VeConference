import { getAuthToken } from "./auth.js";
import { BackgroundProcessor, supportsBackgroundProcessors } from "https://esm.sh/@livekit/track-processors@0.7.2";
import { KrispNoiseFilter } from "https://esm.sh/@livekit/krisp-noise-filter@0.1.3";
import * as LivekitClient from "https://esm.sh/livekit-client@2.20.1";

const { Room, RoomEvent, Track, DataPacket_Kind, VideoQuality } = LivekitClient;

// ==========================================
// PHASE A: PERFORMANCE CONSTANTS
// ==========================================
const MAX_VISIBLE_TILES = 9; // Max simultaneous full-quality video tiles

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
let activePoll = null;
let localVotedOption = null;
let qaQuestions = [];
let localQaUpvoted = new Set();
let newQaCount = 0;

let currentRoom = null;
let userName = "Anonymous";
let pendingRoomId = null;
let isMicEnabled = true;
let isVideoEnabled = true;
let isScreenSharing = false;
let currentFacingMode = 'user';
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

// ==========================================
// PHASE A: ACTIVE SPEAKER TRACKING
// ==========================================
/** Set of participant identities who are currently active speakers (from LiveKit events) */
let activeSpeakerSet = new Set();

/**
 * PHASE A: Ordered list of remote participant identities for the grid.
 * Active speakers float to the front. This is the source of truth for rendering order.
 */
let participantOrder = [];

// ==========================================
// PHASE B: MEMORY LEAK PREVENTION MAPS
// ==========================================
/**
 * Stores per-participant audio analysis resources so they can be properly torn down.
 * Key: participantIdentity, Value: { analyser, rafId, source }
 */
const speakingAnalysers = new Map();

/**
 * Shared AudioContext for speaking indicators (reused, not created per-participant).
 */
let sharedAudioContext = null;

/**
 * PHASE B: Keyed Map of participant identity -> DOM element for the People sidebar.
 * Prevents full innerHTML wipe on every event.
 */
const participantDomMap = new Map();

// --- TOAST: Pooled singleton element ---
let _toastElement = null;
let _toastTimeout = null;
function _getToastEl() {
    if (!_toastElement) {
        _toastElement = document.createElement('div');
        _toastElement.style.cssText = `
            position: fixed; bottom: 120px; left: 50%; transform: translateX(-50%);
            color: white; padding: 12px 24px; border-radius: 12px; z-index: 9999;
            font-weight: 600; box-shadow: 0 10px 25px rgba(0,0,0,0.5);
            text-align: center; max-width: 90%; pointer-events: none;
            transition: opacity 0.4s ease; opacity: 0;
        `;
        document.body.appendChild(_toastElement);
    }
    return _toastElement;
}

function showToast(message, isError = false) {
    const toast = _getToastEl();
    toast.textContent = message;
    toast.style.backgroundColor = isError ? '#ef4444' : '#22c55e';
    toast.style.opacity = '1';
    if (_toastTimeout) clearTimeout(_toastTimeout);
    _toastTimeout = setTimeout(() => {
        toast.style.opacity = '0';
    }, 3500);
}
window.showToast = showToast;

// --- URL Parsing ---
window.addEventListener('DOMContentLoaded', () => {
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
        if (window.openAuthModal) { window.openAuthModal(true); }
        else { alert("Please log in to start a new meeting."); }
        return;
    }
    const isVisible = newMeetingDropdown.style.display === 'block';
    newMeetingDropdown.style.display = isVisible ? 'none' : 'block';
});
window.addEventListener('click', () => { newMeetingDropdown.style.display = 'none'; });

scheduleMeetingBtn.addEventListener('click', () => { scheduleModal.style.display = 'flex'; });
instantMeetingBtn.addEventListener('click', () => { initiateJoinFlow(generateRoomCode()); });

joinBtn.addEventListener('click', () => {
    const code = roomIdInput.value.trim();
    if (code) initiateJoinFlow(code);
});
roomIdInput.addEventListener('keypress', (e) => {
    if (e.key === 'Enter') { const code = roomIdInput.value.trim(); if (code) initiateJoinFlow(code); }
});

function generateRoomCode() {
    return 'la-vie-' + Date.now().toString().substring(7);
}

function initiateJoinFlow(roomId) {
    try {
        const url = new URL(roomId);
        const urlRoom = url.searchParams.get('room');
        if (urlRoom) roomId = urlRoom;
    } catch(e) {}
    pendingRoomId = roomId;
    const user = window.firebaseAuth && window.firebaseAuth.currentUser;
    if (user && user.displayName) {
        userName = user.displayName;
        startCall(pendingRoomId);
    } else {
        preJoinModal.style.display = 'flex';
    }
}

preJoinSubmitBtn.addEventListener('click', () => {
    userName = userNameInput.value.trim() || "Anonymous";
    preJoinModal.style.display = 'none';
    startCall(pendingRoomId);
});

// ==========================================
// CORE CALL LOGIC
// ==========================================
async function startCall(roomId) {
    try {
        joinScreen.style.display = 'none';
        appLayout.style.display = 'flex';
        mediaControls.style.display = 'flex';
        meetingInfo.innerHTML = `
            <div style="display: flex; align-items: center; gap: 10px; background: rgba(0,0,0,0.4); padding: 8px 16px; border-radius: 20px; border: 1px solid rgba(255,255,255,0.1);">
                <div class="meeting-code" style="margin: 0;">${roomId}</div>
                <button class="copy-link-btn" title="Copy Meeting Code" onclick="navigator.clipboard.writeText('${roomId}'); window.showToast('Meeting code copied!')" style="background: transparent; border: none; color: var(--text-muted); cursor: pointer; display: flex; align-items: center; padding: 4px; transition: color 0.2s;">
                    <span class="material-symbols-outlined" style="font-size: 20px;">content_copy</span>
                </button>
            </div>
        `;
        const peerId = Math.random().toString(36).substring(2, 10);

        const fbToken = await getAuthToken();
        const headers = {};
        if (fbToken) { headers['Authorization'] = `Bearer ${fbToken}`; }

        const response = await fetch(`/token/${roomId}/${peerId}?name=${encodeURIComponent(userName)}`, { headers });
        if (!response.ok) throw new Error("Failed to get token");
        const { token, is_admin } = await response.json();
        isAdmin = is_admin || false;

        const toggleRecordBtn = document.getElementById('toggleRecordBtn');
        if (isAdmin && toggleRecordBtn) { toggleRecordBtn.style.display = 'flex'; }

        const muteAllBtn = document.getElementById('muteAllBtn');
        if (isAdmin && muteAllBtn) {
            muteAllBtn.style.display = 'flex';
            muteAllBtn.onclick = async () => {
                if (!currentRoom) return;
                const data = new TextEncoder().encode('__MUTE_ALL__');
                await currentRoom.localParticipant.publishData(data, { reliable: true });
                showToast('Muted all other participants');
            };
        }

        currentRoom = new Room({
            adaptiveStream: true,
            dynacast: true,
            videoCaptureDefaults: { facingMode: currentFacingMode }
        });

        // ======================================
        // PHASE A: ACTIVE SPEAKER EVENT
        // ======================================
        currentRoom.on(RoomEvent.ActiveSpeakersChanged, (speakers) => {
            activeSpeakerSet.clear();
            speakers.forEach(p => activeSpeakerSet.add(p.identity));

            // Update speaking CSS classes using event data — no per-participant RAF loop needed
            videoGrid.querySelectorAll('.video-wrapper:not(.local)').forEach(wrapper => {
                const id = wrapper.dataset.identity;
                if (id) {
                    wrapper.classList.toggle('speaking', activeSpeakerSet.has(id));
                }
            });

            // Re-sort grid: active speakers rise to the front
            _reorderGridByActiveSpeakers();
        });

        currentRoom.on(RoomEvent.TrackSubscribed, (track, publication, participant) => {
            if (track.kind === 'video') {
                attachVideoTrack(track, participant, publication.source);
            } else if (track.kind === 'audio') {
                const audioElement = track.attach();
                document.body.appendChild(audioElement);

                // Route to recording if active
                if (recordingAudioContext && recordingDestinationNode && track.mediaStreamTrack) {
                    if (!audioSourceNodes.has(track.sid)) {
                        const source = recordingAudioContext.createMediaStreamSource(new MediaStream([track.mediaStreamTrack]));
                        source.connect(recordingDestinationNode);
                        audioSourceNodes.set(track.sid, source);
                    }
                }
            }
            // Update participant order and subscription qualities
            _updateParticipantOrder();
            _applySubscriptionQualities();
            renderParticipants();
        });

        currentRoom.on(RoomEvent.TrackUnsubscribed, (track, publication, participant) => {
            track.detach();
            if (track.kind === 'video') {
                const wrapper = document.getElementById(`wrapper-${participant.identity}-${publication.source}`);
                if (wrapper) wrapper.remove();
                updateVideoGridClass();
            }
            // PHASE B: Tear down audio analyser for this participant if they fully leave
            // (full cleanup happens in ParticipantDisconnected)
            _updateParticipantOrder();
            _applySubscriptionQualities();
        });

        currentRoom.on(RoomEvent.ParticipantConnected, (participant) => {
            appendSystemMessage(`${participant.name || 'Anonymous'} joined the room.`);
            _updateParticipantOrder();
            renderParticipants();
        });

        currentRoom.on(RoomEvent.ParticipantDisconnected, (participant) => {
            appendSystemMessage(`${participant.name || 'Anonymous'} left the room.`);
            const wrappers = document.querySelectorAll(`[id^="wrapper-${participant.identity}-"]`);
            wrappers.forEach(w => w.remove());
            updateVideoGridClass();

            // PHASE B: Clean up speaking analyser for disconnected participant
            _teardownSpeakingIndicator(participant.identity);

            _updateParticipantOrder();
            _applySubscriptionQualities();
            renderParticipants();
        });

        currentRoom.on(RoomEvent.DataReceived, async (payload, participant, kind, topic) => {
            const strData = new TextDecoder().decode(payload);

            if (strData === '__MUTE_ALL__') {
                if (currentRoom.localParticipant && isMicEnabled) {
                    await currentRoom.localParticipant.setMicrophoneEnabled(false);
                    isMicEnabled = false;
                    toggleMicBtn.classList.remove('active');
                    toggleMicBtn.querySelector('.material-symbols-outlined').textContent = 'mic_off';
                    showToast('The host has muted your microphone.', true);
                }
                return;
            } else if (strData.startsWith('__MUTE_PARTICIPANT__:')) {
                const targetId = strData.substring('__MUTE_PARTICIPANT__:'.length);
                if (currentRoom.localParticipant && currentRoom.localParticipant.identity === targetId) {
                    if (isMicEnabled) {
                        await currentRoom.localParticipant.setMicrophoneEnabled(false);
                        isMicEnabled = false;
                        toggleMicBtn.classList.remove('active');
                        toggleMicBtn.querySelector('.material-symbols-outlined').textContent = 'mic_off';
                        showToast('The host has muted your microphone.', true);
                    }
                }
                return;
            }

            let data;
            try { data = JSON.parse(strData); }
            catch (e) { data = { type: 'chat', text: strData, sender: participant ? participant.name : 'Unknown' }; }

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

        try {
            const configResponse = await fetch('/tunnel-config');
            const config = await configResponse.json();
            if (config.livekit_url) { livekitUrl = config.livekit_url; }
        } catch (e) {
            console.error("Failed to fetch tunnel config, using fallback:", e);
        }
        await currentRoom.connect(livekitUrl, token);
        console.log("Connected to LiveKit!");

        await currentRoom.localParticipant.enableCameraAndMicrophone();

        try {
            if (supportsBackgroundProcessors()) {
                backgroundProcessor = BackgroundProcessor({ mode: 'disabled' });
                const videoTrack = currentRoom.localParticipant.getTrackPublication(Track.Source.Camera)?.videoTrack;
                if (videoTrack) { await videoTrack.setProcessor(backgroundProcessor); }
            }
        } catch (e) { console.warn("Background processor initialization failed", e); }

        try { krispFilter = KrispNoiseFilter(); }
        catch (e) { console.warn("Krisp noise filter initialization failed", e); }

        _updateParticipantOrder();
        _applySubscriptionQualities();
        updateVideoGridClass();
        renderParticipants();

        chatInput.disabled = false;
        sendBtn.disabled = false;
        appendSystemMessage("You connected to the room.");
        window.history.pushState({}, '', `?room=${roomId}`);

    } catch (err) {
        console.error("Connection error:", err);
        showToast("Could not connect: " + err.message, true);
        leaveCall();
    }
}

// ==========================================
// PHASE A: ACTIVE SPEAKER HELPERS
// ==========================================

/**
 * Rebuilds participantOrder putting active speakers first,
 * then reorders existing DOM tiles to match.
 */
function _updateParticipantOrder() {
    if (!currentRoom) return;
    const allRemote = [];
    currentRoom.remoteParticipants.forEach(p => allRemote.push(p.identity));

    // Sort: active speakers first, then the rest in stable order
    allRemote.sort((a, b) => {
        const aActive = activeSpeakerSet.has(a);
        const bActive = activeSpeakerSet.has(b);
        if (aActive && !bActive) return -1;
        if (!aActive && bActive) return 1;
        return 0;
    });
    participantOrder = allRemote;
}

/**
 * Re-orders DOM video tiles without re-creating them,
 * purely by repositioning existing elements.
 */
function _reorderGridByActiveSpeakers() {
    if (!currentRoom || !videoGrid) return;
    _updateParticipantOrder();

    // Move tiles in priority order (local is always first/pinned in HTML)
    participantOrder.forEach((identity, index) => {
        // Try camera tile first, then screenshare
        const cameraTile = document.getElementById(`wrapper-${identity}-${Track.Source.Camera}`);
        const screenTile = document.getElementById(`wrapper-${identity}-${Track.Source.ScreenShare}`);
        if (cameraTile) videoGrid.appendChild(cameraTile);
        if (screenTile) videoGrid.appendChild(screenTile);
    });
}

/**
 * PHASE A: Sets subscription quality based on tile visibility.
 * Tiles beyond MAX_VISIBLE_TILES get VideoQuality.LOW (server sends low-res).
 * Top tiles get VideoQuality.HIGH.
 */
function _applySubscriptionQualities() {
    if (!currentRoom) return;

    let visibleCount = 1; // local is always visible
    participantOrder.forEach((identity, index) => {
        const participant = currentRoom.remoteParticipants.get(identity);
        if (!participant) return;

        const isVisible = visibleCount < MAX_VISIBLE_TILES;
        const quality = isVisible ? VideoQuality.HIGH : VideoQuality.LOW;

        participant.videoTrackPublications.forEach(pub => {
            if (pub.track && typeof pub.setVideoQuality === 'function') {
                pub.setVideoQuality(quality);
            }
        });

        // Show/hide the tile element based on MAX_VISIBLE_TILES
        const cameraTile = document.getElementById(`wrapper-${identity}-${Track.Source.Camera}`);
        const screenTile = document.getElementById(`wrapper-${identity}-${Track.Source.ScreenShare}`);
        if (cameraTile) cameraTile.style.display = isVisible ? '' : 'none';
        if (screenTile) screenTile.style.display = isVisible ? '' : 'none';

        if (isVisible) visibleCount++;
    });

    _updateOverflowIndicator();
}

/** Shows a "+N more" badge when participants exceed MAX_VISIBLE_TILES */
function _updateOverflowIndicator() {
    let overflowBadge = document.getElementById('tile-overflow-badge');
    const hiddenCount = Math.max(0, participantOrder.length - (MAX_VISIBLE_TILES - 1));

    if (hiddenCount > 0) {
        if (!overflowBadge) {
            overflowBadge = document.createElement('div');
            overflowBadge.id = 'tile-overflow-badge';
            overflowBadge.style.cssText = `
                display: flex; align-items: center; justify-content: center;
                background: rgba(168,85,247,0.2); border: 1px solid rgba(168,85,247,0.4);
                border-radius: 20px; color: var(--text); font-size: 1.1rem; font-weight: 700;
                aspect-ratio: 16/9;
            `;
            videoGrid.appendChild(overflowBadge);
        }
        overflowBadge.textContent = `+${hiddenCount} more`;
        overflowBadge.style.display = 'flex';
    } else if (overflowBadge) {
        overflowBadge.style.display = 'none';
    }
}

// ==========================================
// PHASE B: SPEAKING INDICATOR (FIXED)
// ==========================================

/**
 * Sets up a speaking indicator for a remote participant using
 * a shared AudioContext. Stores resources in speakingAnalysers
 * map so they can be properly torn down when the participant leaves.
 */
function setupSpeakingIndicator(audioTrack, participantIdentity) {
    // PHASE B: Reuse a single shared AudioContext
    if (!sharedAudioContext) {
        sharedAudioContext = new (window.AudioContext || window.webkitAudioContext)();
    }

    // PHASE B: Don't create duplicate analysers
    if (speakingAnalysers.has(participantIdentity)) return;

    try {
        const mediaStreamTrack = audioTrack.mediaStreamTrack;
        if (!mediaStreamTrack) return;

        const source = sharedAudioContext.createMediaStreamSource(new MediaStream([mediaStreamTrack]));
        const analyser = sharedAudioContext.createAnalyser();
        analyser.fftSize = 256;
        source.connect(analyser);
        const dataArray = new Uint8Array(analyser.frequencyBinCount);
        let rafId = null;

        function checkVolume() {
            if (!currentRoom || !speakingAnalysers.has(participantIdentity)) return;
            rafId = requestAnimationFrame(checkVolume);
            analyser.getByteFrequencyData(dataArray);
            let sum = 0;
            for (let i = 0; i < dataArray.length; i++) sum += dataArray[i];
            const average = sum / dataArray.length;
            // Only update if NOT already tracked by the ActiveSpeakers event
            // (the event updates the class more accurately)
            const wrapper = document.getElementById(`wrapper-${participantIdentity}-${Track.Source.Camera}`);
            if (wrapper && !activeSpeakerSet.has(participantIdentity)) {
                wrapper.classList.toggle('speaking', average > 15);
            }
        }

        rafId = requestAnimationFrame(checkVolume);

        // PHASE B: Store the resources so we can tear them down
        speakingAnalysers.set(participantIdentity, { analyser, source, rafId });

    } catch (e) {
        console.warn("Could not setup speaking indicator", e);
    }
}

/**
 * PHASE B: Properly tears down a participant's speaking indicator resources,
 * preventing the memory leak of orphaned animation loops.
 */
function _teardownSpeakingIndicator(participantIdentity) {
    const resources = speakingAnalysers.get(participantIdentity);
    if (!resources) return;

    if (resources.rafId) cancelAnimationFrame(resources.rafId);
    try { resources.source.disconnect(); } catch(e) {}
    try { resources.analyser.disconnect(); } catch(e) {}

    speakingAnalysers.delete(participantIdentity);
}

// ==========================================
// LEAVE CALL
// ==========================================
function leaveCall() {
    if (currentRoom) {
        currentRoom.disconnect();
        currentRoom = null;
    }

    appLayout.style.display = 'none';
    joinScreen.style.display = 'block';
    window.history.pushState({}, '', window.location.pathname);

    // PHASE B: Clean up ALL speaking analysers on leave
    speakingAnalysers.forEach((_, identity) => _teardownSpeakingIndicator(identity));
    speakingAnalysers.clear();
    activeSpeakerSet.clear();
    participantOrder = [];
    participantDomMap.clear();

    if (sharedAudioContext) {
        sharedAudioContext.close();
        sharedAudioContext = null;
    }

    const wrappers = videoGrid.querySelectorAll('.video-wrapper:not(.local)');
    wrappers.forEach(w => w.remove());

    // Remove overflow badge if present
    const badge = document.getElementById('tile-overflow-badge');
    if (badge) badge.remove();

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

    activePoll = null;
    localVotedOption = null;
    qaQuestions = [];
    localQaUpvoted = new Set();
    newQaCount = 0;
    if (pollQaSidebar) { pollQaSidebar.classList.remove('open'); isPollQaOpen = false; }
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
        await new Promise(r => setTimeout(r, 400));
        await currentRoom.localParticipant.setCameraEnabled(true, { facingMode: currentFacingMode });
        const pub = currentRoom.localParticipant.getTrackPublication(Track.Source.Camera);
        if (pub && pub.videoTrack) { pub.videoTrack.attach(localVideo); }
    });
}

const isMobileDevice = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent) || (navigator.maxTouchPoints && navigator.maxTouchPoints > 2);
if (isMobileDevice && toggleScreenBtn) { toggleScreenBtn.style.display = 'none'; }

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
chatInput.addEventListener('keypress', (e) => { if (e.key === 'Enter') sendMessage(); });

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

// ==========================================
// PHASE B: KEYED PARTICIPANT LIST
// ==========================================
/**
 * Diffs the participant list instead of rebuilding innerHTML from scratch.
 * Adds new participants, removes disconnected ones, updates existing ones.
 */
function renderParticipants() {
    if (!currentRoom || !peopleList) return;

    const currentIds = new Set();

    // Handle local participant
    const local = currentRoom.localParticipant;
    if (local) {
        currentIds.add('local-' + local.identity);
        let el = participantDomMap.get('local-' + local.identity);
        if (!el) {
            el = createParticipantElement(local, true);
            participantDomMap.set('local-' + local.identity, el);
            peopleList.prepend(el);
        } else {
            _updateParticipantElement(el, local, true);
        }
    }

    // Handle remote participants
    currentRoom.remoteParticipants.forEach((p) => {
        const key = 'remote-' + p.identity;
        currentIds.add(key);
        let el = participantDomMap.get(key);
        if (!el) {
            el = createParticipantElement(p, false);
            participantDomMap.set(key, el);
            peopleList.appendChild(el);
        } else {
            _updateParticipantElement(el, p, false);
        }
    });

    // Remove elements for participants who have left
    participantDomMap.forEach((el, key) => {
        if (!currentIds.has(key)) {
            el.remove();
            participantDomMap.delete(key);
        }
    });
}

function _updateParticipantElement(el, participant, isLocal) {
    const name = participant.name || participant.identity;
    const hasHand = raisedHands.has(participant.identity);
    const nameEl = el.querySelector('.participant-name');
    if (nameEl) {
        nameEl.textContent = `${name}${isLocal ? ' (You)' : ''}${hasHand ? ' ✋' : ''}`;
    }
}

function createParticipantElement(participant, isLocal) {
    const div = document.createElement('div');
    div.className = 'participant-item';

    const name = participant.name || participant.identity;
    const initial = name.charAt(0).toUpperCase();

    const infoDiv = document.createElement('div');
    infoDiv.className = 'participant-info';

    const avatarDiv = document.createElement('div');
    avatarDiv.className = 'participant-avatar';
    avatarDiv.textContent = initial;

    const nameDiv = document.createElement('div');
    nameDiv.className = 'participant-name';
    nameDiv.textContent = `${name}${isLocal ? ' (You)' : ''}${raisedHands.has(participant.identity) ? ' ✋' : ''}`;

    infoDiv.appendChild(avatarDiv);
    infoDiv.appendChild(nameDiv);
    div.appendChild(infoDiv);

    if (isAdmin && !isLocal) {
        let audioTrackSid = null;
        participant.audioTrackPublications.forEach(pub => {
            if (pub.trackSid) audioTrackSid = pub.trackSid;
        });

        const actionsDiv = document.createElement('div');
        actionsDiv.className = 'participant-actions';

        if (audioTrackSid) {
            const muteBtn = document.createElement('button');
            muteBtn.className = 'action-btn';
            muteBtn.title = 'Mute';
            muteBtn.innerHTML = '<span class="material-symbols-outlined">mic_off</span>';
            muteBtn.addEventListener('click', () => muteParticipant(participant.identity, audioTrackSid));
            actionsDiv.appendChild(muteBtn);
        }

        const kickBtn = document.createElement('button');
        kickBtn.className = 'action-btn kick-btn';
        kickBtn.title = 'Remove';
        kickBtn.innerHTML = '<span class="material-symbols-outlined">person_remove</span>';
        kickBtn.addEventListener('click', () => kickParticipant(participant.identity));
        actionsDiv.appendChild(kickBtn);

        div.appendChild(actionsDiv);
    }

    return div;
}

// Kept as window functions for compatibility with any HTML onclick attrs
async function muteParticipant(identity, trackSid) {
    if (!isAdmin || !currentRoom) return;
    try {
        const data = new TextEncoder().encode(`__MUTE_PARTICIPANT__:${identity}`);
        await currentRoom.localParticipant.publishData(data, { reliable: true });
        showToast("Participant muted");
    } catch(err) { showToast("Error muting participant", true); }
}
window.muteParticipant = muteParticipant;

async function kickParticipant(identity) {
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
    } catch(err) { showToast("Error removing participant", true); }
}
window.kickParticipant = kickParticipant;

function attachVideoTrack(track, participant, source) {
    let wrapper = document.getElementById(`wrapper-${participant.identity}-${source}`);
    if (!wrapper) {
        wrapper = document.createElement('div');
        wrapper.className = 'video-wrapper';
        wrapper.id = `wrapper-${participant.identity}-${source}`;
        wrapper.dataset.identity = participant.identity; // PHASE A: for speaking class lookup

        const label = document.createElement('span');
        label.className = 'label';
        const srcText = source === Track.Source.ScreenShare ? "'s Screen" : "";
        label.textContent = (participant.name || participant.identity) + srcText;

        const pinBtn = document.createElement('button');
        pinBtn.className = 'pin-overlay-btn';
        pinBtn.title = 'Spotlight Video';
        pinBtn.innerHTML = '<span class="material-symbols-outlined">push_pin</span>';
        pinBtn.addEventListener('click', (e) => { e.stopPropagation(); togglePin(wrapper.id); });

        const pipBtn = document.createElement('button');
        pipBtn.className = 'pip-overlay-btn';
        pipBtn.title = 'Picture in Picture';
        pipBtn.innerHTML = '<span class="material-symbols-outlined">picture_in_picture_alt</span>';
        pipBtn.addEventListener('click', async (e) => {
            e.stopPropagation();
            const videoElement = wrapper.querySelector('video');
            if (videoElement) {
                if (document.pictureInPictureElement) { await document.exitPictureInPicture(); }
                else if (videoElement.requestPictureInPicture) { await videoElement.requestPictureInPicture(); }
            }
        });

        wrapper.addEventListener('dblclick', () => togglePin(wrapper.id));
        wrapper.appendChild(label);
        wrapper.appendChild(pinBtn);
        wrapper.appendChild(pipBtn);

        if (isAdmin && participant && currentRoom && participant.identity !== currentRoom.localParticipant.identity && source !== Track.Source.ScreenShare) {
            const videoMuteBtn = document.createElement('button');
            videoMuteBtn.className = 'video-mute-overlay-btn';
            videoMuteBtn.title = 'Mute Participant';
            videoMuteBtn.innerHTML = '<span class="material-symbols-outlined" style="font-size: 18px;">mic_off</span>';
            videoMuteBtn.style.cssText = 'position:absolute;top:10px;left:10px;background:rgba(0,0,0,0.6);color:#ef4444;border:1px solid rgba(255,255,255,0.1);border-radius:8px;padding:6px;cursor:pointer;z-index:10;transition:all 0.2s;';
            videoMuteBtn.onmouseover = () => { videoMuteBtn.style.background = 'rgba(239,68,68,0.2)'; };
            videoMuteBtn.onmouseout = () => { videoMuteBtn.style.background = 'rgba(0,0,0,0.6)'; };
            videoMuteBtn.addEventListener('click', (e) => { e.stopPropagation(); muteParticipant(participant.identity); });
            wrapper.appendChild(videoMuteBtn);
        }

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
        pinBtn.addEventListener('click', (e) => { e.stopPropagation(); togglePin(localWrapper.id); });
    }
}

// ==========================================
// RECORDING
// ==========================================
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
        mediaRecorder.ondataavailable = (e) => { if (e.data.size > 0) recordedChunks.push(e.data); };
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
    if (mediaRecorder && mediaRecorder.state !== 'inactive') { mediaRecorder.stop(); }
    mediaRecorder = null;
    if (recordingAudioContext) { recordingAudioContext.close(); recordingAudioContext = null; }
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

// ==========================================
// THEME TOGGLING
// ==========================================
const themeToggleBtn = document.getElementById('themeToggleBtn');
const themeIcon = document.getElementById('themeIcon');

function setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('theme', theme);
    if (themeIcon) { themeIcon.textContent = theme === 'dark' ? 'light_mode' : 'dark_mode'; }
}

const savedTheme = localStorage.getItem('theme') || 'dark';
setTheme(savedTheme);

if (themeToggleBtn) {
    themeToggleBtn.addEventListener('click', () => {
        const currentTheme = document.documentElement.getAttribute('data-theme');
        setTheme(currentTheme === 'dark' ? 'light' : 'dark');
    });
}

// ==========================================
// REACTIONS & HAND RAISE
// ==========================================
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
    const wrapper = wrappers[0];
    const emojiEl = document.createElement('div');
    emojiEl.className = 'floating-emoji';
    emojiEl.textContent = emoji;
    wrapper.appendChild(emojiEl);
    setTimeout(() => { if (emojiEl.parentNode) emojiEl.remove(); }, 2500);
}

function updateHandRaiseUI(identity, isRaised) {
    if (!identity) return;
    if (isRaised) { raisedHands.add(identity); } else { raisedHands.delete(identity); }
    const wrappers = document.querySelectorAll(`[id^="wrapper-${identity}-"]`);
    wrappers.forEach(wrapper => {
        let badge = wrapper.querySelector('.hand-badge');
        if (isRaised && !badge) {
            badge = document.createElement('div');
            badge.className = 'hand-badge';
            badge.textContent = '✋';
            wrapper.appendChild(badge);
        } else if (!isRaised && badge) { badge.remove(); }
    });
    renderParticipants();
}

// ==========================================
// AI EFFECTS
// ==========================================
if (toggleEffectsBtn) {
    toggleEffectsBtn.addEventListener('click', () => { effectsModal.style.display = 'flex'; });
    closeEffectsBtn.addEventListener('click', () => { effectsModal.style.display = 'none'; });
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
                if (effect === 'none') { await backgroundProcessor.switchTo({ mode: 'disabled' }); }
                else if (effect === 'blur') { await backgroundProcessor.switchTo({ mode: 'background-blur', blurRadius: 15 }); }
                else { await backgroundProcessor.switchTo({ mode: 'virtual-background', imagePath: `/static/assets/${effect}.png` }); }
            } catch(e) {
                console.error("Error switching background effect", e);
                showToast("Failed to apply effect. Try again.", true);
            }
        });
    });
}

if (toggleNoiseBtn) {
    toggleNoiseBtn.addEventListener('click', async () => {
        if (!currentRoom || !krispFilter) { showToast("Noise cancellation not available.", true); return; }
        const audioTrack = currentRoom.localParticipant.getTrackPublication(Track.Source.Microphone)?.audioTrack;
        if (!audioTrack) return;
        isNoiseCancellationEnabled = !isNoiseCancellationEnabled;
        toggleNoiseBtn.classList.toggle('active', isNoiseCancellationEnabled);
        try {
            if (isNoiseCancellationEnabled) { await audioTrack.setProcessor(krispFilter); showToast("AI Noise Cancellation Enabled"); }
            else { await audioTrack.stopProcessor(); showToast("AI Noise Cancellation Disabled"); }
        } catch(e) {
            console.error("Error toggling noise filter", e);
            isNoiseCancellationEnabled = !isNoiseCancellationEnabled;
            toggleNoiseBtn.classList.toggle('active', isNoiseCancellationEnabled);
            showToast("Failed to toggle noise cancellation.", true);
        }
    });
}

// ==========================================
// WHITEBOARD
// ==========================================
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
            broadcast({ type: 'whiteboard_toggle', state: true, senderId: currentRoom.localParticipant.identity });
        } else {
            mainColumn.classList.remove('with-whiteboard');
            whiteboardContainer.classList.remove('active');
            broadcast({ type: 'whiteboard_toggle', state: false, senderId: currentRoom.localParticipant.identity });
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

if (togglePollsBtn) {
    togglePollsBtn.addEventListener('click', () => {
        isPollQaOpen = !isPollQaOpen;
        pollQaSidebar.classList.toggle('open', isPollQaOpen);
        togglePollsBtn.classList.toggle('active', isPollQaOpen);
        if (isPollQaOpen) { newQaCount = 0; if (qaBadge) qaBadge.style.display = 'none'; }
    });
}

if (closePollQaBtn) {
    closePollQaBtn.addEventListener('click', () => {
        isPollQaOpen = false;
        pollQaSidebar.classList.remove('open');
        togglePollsBtn.classList.remove('active');
    });
}

document.querySelectorAll('.pq-tab').forEach(tab => {
    tab.addEventListener('click', () => {
        document.querySelectorAll('.pq-tab').forEach(t => t.classList.remove('active'));
        tab.classList.add('active');
        const which = tab.getAttribute('data-tab');
        document.getElementById('tabContentPolls').style.display = which === 'polls' ? 'flex' : 'none';
        document.getElementById('tabContentQA').style.display = which === 'qa' ? 'flex' : 'none';
    });
});

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
            const span1 = document.createElement('span'); span1.textContent = opt;
            const span2 = document.createElement('span');
            const strong = document.createElement('strong'); strong.textContent = pct + '%';
            const voteCount = document.createElement('span'); voteCount.className = 'poll-votes-count'; voteCount.textContent = `(${votes})`;
            span2.appendChild(strong); span2.appendChild(voteCount);
            btn.appendChild(span1); btn.appendChild(span2);
            if (localVotedOption === null) { btn.addEventListener('click', () => castVote(idx)); }
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
    if (!isPollQaOpen) { if (qaBadge) qaBadge.style.display = 'block'; }
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

const addPollOptionBtn = document.getElementById('addPollOptionBtn');
if (addPollOptionBtn) {
    addPollOptionBtn.addEventListener('click', () => {
        const container = document.getElementById('pollOptionsContainer');
        const count = container.querySelectorAll('.poll-option-input').length + 1;
        if (count > 6) { showToast('Max 6 options allowed.', true); return; }
        const inp = document.createElement('input');
        inp.type = 'text'; inp.className = 'modal-input poll-option-input'; inp.placeholder = `Option ${count}`;
        container.appendChild(inp);
    });
}
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
        document.getElementById('pollQuestionInput').value = '';
        optInputs.forEach((inp, i) => { inp.value = ''; if (i >= 2) inp.remove(); });
    });
}
const endPollBtn = document.getElementById('endPollBtn');
if (endPollBtn) {
    endPollBtn.addEventListener('click', () => { handlePollEnd(); broadcast({ type: 'poll_end' }); });
}

// ---- Q&A ----
function renderQaUI() {
    const list = document.getElementById('qaQuestionsList');
    const emptyState = document.getElementById('qaEmptyState');
    if (!list) return;
    list.querySelectorAll('.qa-question-card').forEach(c => c.remove());
    if (qaQuestions.length === 0) {
        if (emptyState) emptyState.style.display = 'flex';
        return;
    }
    if (emptyState) emptyState.style.display = 'none';
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

        // Use createElement for security (no innerHTML with user data)
        const meta = document.createElement('div'); meta.className = 'qa-question-meta';
        const author = document.createElement('span'); author.className = 'qa-question-author'; author.textContent = q.author;
        const time = document.createElement('span'); time.className = 'qa-question-time'; time.textContent = timeStr;
        meta.appendChild(author); meta.appendChild(time);

        const textEl = document.createElement('p'); textEl.className = 'qa-question-text'; textEl.textContent = q.text;

        const actions = document.createElement('div'); actions.className = 'qa-question-actions';
        const upvoteBtn = document.createElement('button');
        upvoteBtn.className = 'qa-upvote-btn' + (hasVoted ? ' voted' : '');
        upvoteBtn.textContent = `👍 ${q.upvotes}`;
        upvoteBtn.addEventListener('click', () => {
            if (localQaUpvoted.has(q.id)) return;
            localQaUpvoted.add(q.id);
            const qObj = qaQuestions.find(x => x.id === q.id);
            if (qObj) qObj.upvotes++;
            renderQaUI();
            broadcast({ type: 'qa_upvote', questionId: q.id });
        });
        actions.appendChild(upvoteBtn);

        if (q.answered) {
            const badge = document.createElement('span'); badge.className = 'qa-answered-badge'; badge.textContent = '✓ Answered';
            actions.appendChild(badge);
        } else if (isAdmin) {
            const ansBtn = document.createElement('button'); ansBtn.className = 'qa-answer-btn'; ansBtn.textContent = 'Mark Answered';
            ansBtn.addEventListener('click', () => { handleQaAnswered(q.id); broadcast({ type: 'qa_answered', questionId: q.id }); });
            actions.appendChild(ansBtn);
        }

        card.appendChild(meta); card.appendChild(textEl); card.appendChild(actions);
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
    if (q) { q.upvotes++; renderQaUI(); }
}
function handleQaAnswered(questionId) {
    const q = qaQuestions.find(x => x.id === questionId);
    if (q) { q.answered = true; renderQaUI(); }
}

const submitQaBtn = document.getElementById('submitQaBtn');
const qaQuestionInput = document.getElementById('qaQuestionInput');
if (submitQaBtn && qaQuestionInput) {
    submitQaBtn.addEventListener('click', () => {
        if (!currentRoom || currentRoom.state !== 'connected') return;
        const text = qaQuestionInput.value.trim();
        if (!text) return;
        const question = {
            id: Date.now().toString(36) + Math.random().toString(36).slice(2),
            author: userName, text, upvotes: 0, answered: false, ts: Date.now()
        };
        handleQaNewQuestion(question);
        broadcast({ type: 'qa_question', question });
        qaQuestionInput.value = '';
    });
    qaQuestionInput.addEventListener('keypress', (e) => { if (e.key === 'Enter') submitQaBtn.click(); });
}
