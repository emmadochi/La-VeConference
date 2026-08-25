import { getAuthToken } from "./auth.js";
import { BackgroundProcessor, supportsBackgroundProcessors } from "https://esm.sh/@livekit/track-processors@0.7.2";
import { KrispNoiseFilter } from "https://esm.sh/@livekit/krisp-noise-filter@0.1.3";
import * as LivekitClient from "https://esm.sh/livekit-client@2.20.1";

const { Room, RoomEvent, Track, DataPacket_Kind, VideoQuality, ExternalE2EEKeyProvider } = LivekitClient;

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
const flipCameraBtnText = document.getElementById('flipCameraBtnText');
const cameraListContainer = document.getElementById('cameraListContainer');
const audioDevicesBtn = document.getElementById('audioDevicesBtn');
const audioDevicesBtnText = document.getElementById('audioDevicesBtnText');
const audioListContainer = document.getElementById('audioListContainer');
const speakerDevicesBtn = document.getElementById('speakerDevicesBtn');
const speakerDevicesBtnText = document.getElementById('speakerDevicesBtnText');
const speakerListContainer = document.getElementById('speakerListContainer');

let availableVideoDevices = [];
let availableAudioInputDevices = [];
let availableAudioOutputDevices = [];
let activeCameraDeviceId = null;
let activeAudioInputDeviceId = null;
let activeAudioOutputDeviceId = null;
const toggleScreenBtn = document.getElementById('toggleScreenBtn');
const toggleChatBtn = document.getElementById('navChatBtn') || document.getElementById('toggleChatBtn');
const togglePeopleBtn = document.getElementById('navPeopleBtn') || document.getElementById('togglePeopleBtn');
const toggleReactBtn = document.getElementById('toggleReactBtn');
const toggleEffectsBtn = document.getElementById('toggleEffectsBtn');
const effectsModal = document.getElementById('effectsModal');
const closeEffectsBtn = document.getElementById('closeEffectsBtn');
const effectsGrid = document.getElementById('effectsGrid');
const toggleNoiseBtn = document.getElementById('toggleNoiseBtn');
const toggleWhiteboardBtn = document.getElementById('navWhiteboardBtn') || document.getElementById('toggleWhiteboardBtn');
const mainColumn = document.getElementById('mainColumn');
const whiteboardContainer = document.getElementById('whiteboardContainer');
const togglePollsBtn = document.getElementById('navPollsBtn') || document.getElementById('togglePollsBtn');
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

/**
 * Universal clipboard copy helper with robust fallbacks.
 * Works seamlessly on HTTPS, HTTP (local network/IP), Mobile Safari, Android Chrome, and WebViews.
 */
async function copyTextToClipboard(text, successMsg = 'Copied to clipboard!', errorMsg = 'Failed to copy.') {
    if (!text) {
        if (typeof showToast === 'function') showToast(errorMsg, true);
        return false;
    }

    let copied = false;

    // 1. Try modern navigator.clipboard API if available (typically HTTPS / localhost)
    if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
        try {
            await navigator.clipboard.writeText(text);
            copied = true;
        } catch (err) {
            console.warn('navigator.clipboard.writeText failed, trying fallback...', err);
        }
    }

    // 2. Fallback using document.execCommand('copy') via temporary textarea
    if (!copied) {
        try {
            const textarea = document.createElement('textarea');
            textarea.value = text;
            textarea.setAttribute('readonly', '');
            textarea.style.position = 'fixed';
            textarea.style.top = '0';
            textarea.style.left = '0';
            textarea.style.opacity = '0';
            textarea.style.pointerEvents = 'none';
            document.body.appendChild(textarea);
            textarea.focus();
            textarea.select();
            textarea.setSelectionRange(0, textarea.value.length);
            
            copied = document.execCommand('copy');
            document.body.removeChild(textarea);
        } catch (fallbackErr) {
            console.warn('document.execCommand fallback failed:', fallbackErr);
        }
    }

    if (copied) {
        if (typeof showToast === 'function') showToast(successMsg);
        return true;
    } else {
        // Last resort manual prompt fallback
        try {
            window.prompt('Copy to clipboard (Ctrl+C / Cmd+C):', text);
            if (typeof showToast === 'function') showToast(successMsg);
            return true;
        } catch (e) {
            if (typeof showToast === 'function') showToast(errorMsg, true);
            return false;
        }
    }
}
window.copyTextToClipboard = copyTextToClipboard;

function getMeetingShareUrl(rId) {
    const rid = rId || (currentRoom ? currentRoom.name : null) || pendingRoomId || (new URLSearchParams(window.location.search)).get('room') || '';
    const origin = window.location.origin;
    const pathname = window.location.pathname;
    if (rid) {
        return `${origin}${pathname}?room=${encodeURIComponent(rid)}`;
    }
    return window.location.href;
}
window.getMeetingShareUrl = getMeetingShareUrl;

function copyMeetingLink(rId) {
    const url = getMeetingShareUrl(rId);
    return copyTextToClipboard(url, 'Meeting link copied to clipboard!');
}
window.copyMeetingLink = copyMeetingLink;

function copyMeetingCode(rId) {
    const rid = rId || (currentRoom ? currentRoom.name : null) || pendingRoomId || (new URLSearchParams(window.location.search)).get('room') || '';
    return copyTextToClipboard(rid, 'Meeting code copied to clipboard!');
}
window.copyMeetingCode = copyMeetingCode;

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
            <span class="material-symbols-outlined" style="font-size: 18px; color: var(--primary, #00E5FF);">info</span>
            <span class="meeting-code" style="font-family: monospace; font-size: 0.9rem; letter-spacing: 0.5px; margin: 0 4px;">${roomId}</span>
            <button class="copy-code-badge-btn" title="Copy Meeting Link" onclick="window.copyMeetingLink('${roomId}')">
                <span class="material-symbols-outlined" style="font-size: 18px;">content_copy</span>
            </button>
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

        const toggleVmixBtn = document.getElementById('toggleVmixBtn');
        if (isAdmin && toggleVmixBtn) { toggleVmixBtn.style.display = 'flex'; }

        const toggleMultiStreamBtn = document.getElementById('toggleMultiStreamBtn');
        if (isAdmin && toggleMultiStreamBtn) { toggleMultiStreamBtn.style.display = 'flex'; }

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

        const e2eeKey = window.location.hash.substring(1) || localStorage.getItem(`e2ee_${roomId}`);
        let e2eeOptions = undefined;
        if (e2eeKey) {
            const keyProvider = new ExternalE2EEKeyProvider();
            keyProvider.setKey(e2eeKey);
            e2eeOptions = {
                keyProvider,
                workerUrl: '/static/e2ee-worker.js'
            };
        }

        currentRoom = new Room({
            adaptiveStream: true,
            dynacast: true,
            videoCaptureDefaults: { facingMode: currentFacingMode },
            e2ee: e2eeOptions
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

        currentRoom.on(RoomEvent.TrackMuted, (publication, participant) => {
            if (publication.kind === 'video') {
                const wrapper = document.getElementById(`wrapper-${participant.identity}-${publication.source}`);
                if (wrapper) wrapper.classList.add('video-muted');
            }
        });

        currentRoom.on(RoomEvent.TrackUnmuted, (publication, participant) => {
            if (publication.kind === 'video') {
                const wrapper = document.getElementById(`wrapper-${participant.identity}-${publication.source}`);
                if (wrapper) wrapper.classList.remove('video-muted');
            }
        });

        currentRoom.on(RoomEvent.ParticipantConnected, (participant) => {
            appendSystemMessage(`${participant.name || 'Anonymous'} joined the room.`);
            if (participant.identity === 'vmix_stage_feed') {
                showToast('Live vMix broadcast stage started!', false);
                spotlightParticipant(participant.identity);
            }
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

            if (strData === '__END_MEETING__') {
                showToast('The host has ended the meeting for everyone.', true);
                leaveCall();
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
                    isWhiteboardActive = true;
                    if (toggleWhiteboardBtn) toggleWhiteboardBtn.classList.add('active');
                    mainColumn.classList.add('with-whiteboard');
                    whiteboardContainer.classList.add('active');
                    if (!whiteboardContainer.querySelector('iframe')) {
                        const iframe = document.createElement('iframe');
                        iframe.src = `https://wbo.ophir.dev/boards/lavie-${currentRoom.name}`;
                        whiteboardContainer.appendChild(iframe);
                    }
                    showToast(`${data.senderId || (participant ? participant.name : 'Someone')} opened the whiteboard.`);
                } else if (!data.state && isWhiteboardActive) {
                    isWhiteboardActive = false;
                    if (toggleWhiteboardBtn) toggleWhiteboardBtn.classList.remove('active');
                    mainColumn.classList.remove('with-whiteboard');
                    whiteboardContainer.classList.remove('active');
                    showToast('Whiteboard closed by host.');
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
                (toggleScreenBtn.querySelector('.btn-text') && (toggleScreenBtn.querySelector('.btn-text').textContent = 'Share'));
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
        await updateCameraDevicesList();
        await updateAudioDevicesList();

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
    (toggleMicBtn.querySelector('.btn-text') && (toggleMicBtn.querySelector('.btn-text').textContent = 'Mute'));
    toggleVideoBtn.classList.add('active');
    toggleVideoBtn.querySelector('.material-symbols-outlined').textContent = 'videocam';
    (toggleVideoBtn.querySelector('.btn-text') && (toggleVideoBtn.querySelector('.btn-text').textContent = 'Hide'));
    toggleScreenBtn.classList.remove('active');
    toggleScreenBtn.querySelector('.material-symbols-outlined').textContent = 'present_to_all';
    (toggleScreenBtn.querySelector('.btn-text') && (toggleScreenBtn.querySelector('.btn-text').textContent = 'Share'));

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

leaveCallBtn.addEventListener('click', () => {
    if (isAdmin) {
        document.getElementById('leaveModal').style.display = 'flex';
    } else {
        leaveCall();
    }
});

const closeLeaveModalBtn = document.getElementById('closeLeaveModalBtn');
const leaveMeetingOnlyBtn = document.getElementById('leaveMeetingOnlyBtn');
const endMeetingForAllBtn = document.getElementById('endMeetingForAllBtn');
if (closeLeaveModalBtn) closeLeaveModalBtn.addEventListener('click', () => document.getElementById('leaveModal').style.display = 'none');
if (leaveMeetingOnlyBtn) leaveMeetingOnlyBtn.addEventListener('click', () => {
    document.getElementById('leaveModal').style.display = 'none';
    leaveCall();
});
if (endMeetingForAllBtn) endMeetingForAllBtn.addEventListener('click', async () => {
    if (!currentRoom) return;
    try {
        const idToken = await getAuthToken();
        await fetch('/api/end_meeting', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${idToken}` },
            body: JSON.stringify({ room_id: currentRoom.name })
        });
        document.getElementById('leaveModal').style.display = 'none';
        leaveCall();
    } catch (e) {
        showToast("Failed to end meeting.", true);
    }
});

// --- vMix Ingest Modal Handler ---
const toggleVmixBtn = document.getElementById('toggleVmixBtn');
const vmixModal = document.getElementById('vmixModal');
const closeVmixModalBtn = document.getElementById('closeVmixModalBtn');
const copyVmixUrlBtn = document.getElementById('copyVmixUrlBtn');
const copyVmixKeyBtn = document.getElementById('copyVmixKeyBtn');

if (toggleVmixBtn) {
    toggleVmixBtn.addEventListener('click', async () => {
        if (!currentRoom) return;
        if (vmixModal) vmixModal.style.display = 'flex';
        const moreOptions = document.getElementById('moreOptionsMenu');
        if (moreOptions) moreOptions.style.display = 'none';

        const rtmpInput = document.getElementById('vmixRtmpUrl');
        const keyInput = document.getElementById('vmixStreamKey');
        if (rtmpInput) rtmpInput.value = 'Fetching credentials...';
        if (keyInput) keyInput.value = 'Fetching credentials...';

        try {
            const idToken = await getAuthToken();
            const headers = { 'Content-Type': 'application/json' };
            if (idToken) {
                headers['Authorization'] = `Bearer ${idToken}`;
            }

            const res = await fetch('/api/create_ingress', {
                method: 'POST',
                headers: headers,
                body: JSON.stringify({ room_id: currentRoom.name })
            });
            const data = await res.json();
            if (res.ok && data.status === 'success') {
                if (rtmpInput) rtmpInput.value = data.rtmp_url;
                if (keyInput) keyInput.value = data.stream_key;
                showToast("vMix RTMP credentials ready!");
            } else {
                const errorDetail = data.detail || "Failed to fetch vMix credentials.";
                if (rtmpInput) rtmpInput.value = "Failed to fetch URL";
                if (keyInput) keyInput.value = "Failed to fetch Key";
                showToast(errorDetail, true);
            }
        } catch (e) {
            console.error("Error fetching vMix ingress credentials:", e);
            if (rtmpInput) rtmpInput.value = "Connection error";
            if (keyInput) keyInput.value = "Connection error";
            showToast("Failed to connect to vMix Ingress service.", true);
        }
    });
}

if (closeVmixModalBtn) {
    closeVmixModalBtn.addEventListener('click', () => {
        if (vmixModal) vmixModal.style.display = 'none';
    });
}

if (copyVmixUrlBtn) {
    copyVmixUrlBtn.addEventListener('click', () => {
        const val = document.getElementById('vmixRtmpUrl')?.value || '';
        copyTextToClipboard(val, "RTMP Server URL copied to clipboard!");
    });
}

if (copyVmixKeyBtn) {
    copyVmixKeyBtn.addEventListener('click', () => {
        const val = document.getElementById('vmixStreamKey')?.value || '';
        copyTextToClipboard(val, "Stream Key copied to clipboard!");
    });
}

// --- Multi-Streaming (RTMP to YouTube/Facebook) & Subscription Handlers ---
const toggleMultiStreamBtn = document.getElementById('toggleMultiStreamBtn');
const multiStreamModal = document.getElementById('multiStreamModal');
const closeMultiStreamModalBtn = document.getElementById('closeMultiStreamModalBtn');
const upgradeModal = document.getElementById('upgradeModal');
const closeUpgradeModalBtn = document.getElementById('closeUpgradeModalBtn');
const userPlanBadge = document.getElementById('userPlanBadge');
const destinationsContainer = document.getElementById('destinationsContainer');
const addNewDestinationBtn = document.getElementById('addNewDestinationBtn');
const newDestForm = document.getElementById('newDestForm');
const cancelDestBtn = document.getElementById('cancelDestBtn');
const saveDestBtn = document.getElementById('saveDestBtn');
const destPlatformSelect = document.getElementById('destPlatformSelect');
const destNameInput = document.getElementById('destNameInput');
const destUrlInput = document.getElementById('destUrlInput');
const destKeyInput = document.getElementById('destKeyInput');
const startMultiStreamBtn = document.getElementById('startMultiStreamBtn');
const activeStreamBanner = document.getElementById('activeStreamBanner');
const activeStreamDetails = document.getElementById('activeStreamDetails');
const stopActiveMultiStreamBtn = document.getElementById('stopActiveMultiStreamBtn');

let currentSubscription = { plan: 'free', can_multistream: false, max_destinations: 0, name: 'Free Tier' };
let currentDestinations = [];
let activeStreamEgressId = null;

// Platform default URL presets
const PLATFORM_PRESETS = {
    youtube: { label: 'YouTube Live', url: 'rtmp://a.rtmp.youtube.com/live2' },
    facebook: { label: 'Facebook Live', url: 'rtmps://live-api-s.facebook.com:443/rtmp/' },
    twitch: { label: 'Twitch Live', url: 'rtmp://live.twitch.tv/app/' },
    custom: { label: 'Custom RTMP', url: '' }
};

if (destPlatformSelect) {
    destPlatformSelect.addEventListener('change', () => {
        const val = destPlatformSelect.value;
        if (PLATFORM_PRESETS[val]) {
            destUrlInput.value = PLATFORM_PRESETS[val].url;
            if (!destNameInput.value || Object.values(PLATFORM_PRESETS).some(p => p.label === destNameInput.value)) {
                destNameInput.value = PLATFORM_PRESETS[val].label;
            }
        }
    });
}

// Layout Picker Handlers
document.querySelectorAll('.layout-option').forEach(opt => {
    opt.addEventListener('click', () => {
        document.querySelectorAll('.layout-option').forEach(o => o.classList.remove('active'));
        opt.classList.add('active');
        const radio = opt.querySelector('input[type="radio"]');
        if (radio) radio.checked = true;
    });
});

async function loadSubscription() {
    try {
        const idToken = await getAuthToken();
        const res = await fetch('/api/user/subscription', {
            headers: { 'Authorization': `Bearer ${idToken}` }
        });
        if (res.ok) {
            const data = await res.json();
            currentSubscription = data.subscription || currentSubscription;
            updateSubscriptionUI();
        }
    } catch (e) {
        console.warn("Could not load subscription details:", e);
    }
}

function updateSubscriptionUI() {
    if (!userPlanBadge) return;
    userPlanBadge.className = 'plan-pill';
    if (currentSubscription.is_admin || currentSubscription.plan === 'enterprise') {
        userPlanBadge.classList.add('enterprise-pill');
        userPlanBadge.textContent = '👑 Enterprise Plan';
    } else if (currentSubscription.plan === 'ministry') {
        userPlanBadge.classList.add('ministry-pill');
        userPlanBadge.textContent = '✨ Ministry Plan';
    } else if (currentSubscription.plan === 'pro') {
        userPlanBadge.classList.add('pro-pill');
        userPlanBadge.textContent = '⭐ Pro Creator Plan';
    } else {
        userPlanBadge.classList.add('free-pill');
        userPlanBadge.textContent = '🔒 Free Tier';
    }
}

async function loadDestinations() {
    try {
        const idToken = await getAuthToken();
        const res = await fetch('/api/streaming/destinations', {
            headers: { 'Authorization': `Bearer ${idToken}` }
        });
        if (res.ok) {
            const data = await res.json();
            currentDestinations = data.destinations || [];
            renderDestinations();
        }
    } catch (e) {
        console.warn("Could not load streaming destinations:", e);
    }
}

function renderDestinations() {
    if (!destinationsContainer) return;
    if (currentDestinations.length === 0) {
        destinationsContainer.innerHTML = `
            <div style="text-align: center; padding: 20px; color: rgba(255,255,255,0.4); font-size: 0.85rem; border: 1px dashed rgba(255,255,255,0.1); border-radius: 8px;">
                <span class="material-symbols-outlined" style="font-size: 2rem; color: rgba(255,255,255,0.2); display: block; margin-bottom: 4px;">broadcast_on_home</span>
                No broadcast destinations configured yet.<br>Click <strong>+ Add Destination</strong> to connect YouTube or Facebook.
            </div>
        `;
        return;
    }

    destinationsContainer.innerHTML = currentDestinations.map((dest, idx) => {
        const tagClass = `dest-tag-${dest.platform || 'custom'}`;
        const isChecked = dest.enabled !== false ? 'checked' : '';
        return `
            <div class="destination-card" data-idx="${idx}">
                <div style="display: flex; align-items: center; gap: 12px;">
                    <input type="checkbox" class="dest-toggle" data-idx="${idx}" ${isChecked} style="accent-color: #00E5FF; transform: scale(1.2); cursor: pointer;">
                    <div>
                        <div style="display: flex; align-items: center; gap: 6px;">
                            <strong style="color: #fff; font-size: 0.88rem;">${escapeHtml(dest.name || 'Stream Channel')}</strong>
                            <span class="dest-platform-tag ${tagClass}">${dest.platform || 'RTMP'}</span>
                        </div>
                        <div style="color: rgba(255,255,255,0.5); font-size: 0.75rem; font-family: monospace;">
                            ${escapeHtml(dest.server_url || '')}
                        </div>
                    </div>
                </div>
                <div style="display: flex; align-items: center; gap: 6px;">
                    <button class="delete-dest-btn" data-idx="${idx}" style="background: none; border: none; color: rgba(255,255,255,0.4); cursor: pointer; padding: 4px; border-radius: 4px; transition: color 0.2s;" title="Delete Destination">
                        <span class="material-symbols-outlined" style="font-size: 1.1rem;">delete</span>
                    </button>
                </div>
            </div>
        `;
    }).join('');

    // Attach destination toggle and delete event listeners
    destinationsContainer.querySelectorAll('.dest-toggle').forEach(chk => {
        chk.addEventListener('change', async (e) => {
            const idx = parseInt(e.target.getAttribute('data-idx'));
            if (currentDestinations[idx]) {
                currentDestinations[idx].enabled = e.target.checked;
                await saveDestinationsToBackend();
            }
        });
    });

    destinationsContainer.querySelectorAll('.delete-dest-btn').forEach(btn => {
        btn.addEventListener('click', async (e) => {
            const idx = parseInt(btn.getAttribute('data-idx'));
            currentDestinations.splice(idx, 1);
            await saveDestinationsToBackend();
            renderDestinations();
        });
    });
}

async function saveDestinationsToBackend() {
    try {
        const idToken = await getAuthToken();
        const res = await fetch('/api/streaming/destinations', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${idToken}`
            },
            body: JSON.stringify({ destinations: currentDestinations })
        });
        if (!res.ok) {
            const err = await res.json();
            showToast(err.detail || "Failed to save destinations", true);
        }
    } catch (e) {
        console.error("Error saving destinations:", e);
    }
}

async function checkRoomStreamingStatus() {
    if (!currentRoom) return;
    try {
        const res = await fetch(`/api/streaming/status/${currentRoom.name}`);
        if (res.ok) {
            const data = await res.json();
            if (data.is_multistreaming) {
                activeStreamEgressId = data.streaming_egress_id;
                showActiveStreamUI(data.destinations_count || 1);
            } else {
                activeStreamEgressId = null;
                hideActiveStreamUI();
            }
        }
    } catch (e) {
        console.warn("Could not check room stream status:", e);
    }
}

function showActiveStreamUI(count) {
    if (activeStreamBanner) {
        activeStreamBanner.style.display = 'flex';
        if (activeStreamDetails) {
            activeStreamDetails.textContent = `Active stream pushing to ${count} destination(s)`;
        }
    }
    if (startMultiStreamBtn) {
        startMultiStreamBtn.style.display = 'none';
    }

    // In-meeting header live badge
    let badge = document.getElementById('liveStreamStatusBadge');
    if (!badge) {
        const infoBar = document.getElementById('meetingInfo');
        if (infoBar) {
            badge = document.createElement('div');
            badge.id = 'liveStreamStatusBadge';
            badge.className = 'live-stream-badge';
            badge.innerHTML = '<span class="pulsing-live-dot" style="width: 8px; height: 8px;"></span> LIVE ON SOCIALS';
            infoBar.appendChild(badge);
        }
    } else {
        badge.style.display = 'inline-flex';
    }
}

function hideActiveStreamUI() {
    if (activeStreamBanner) activeStreamBanner.style.display = 'none';
    if (startMultiStreamBtn) startMultiStreamBtn.style.display = 'flex';
    const badge = document.getElementById('liveStreamStatusBadge');
    if (badge) badge.style.display = 'none';
}

if (toggleMultiStreamBtn) {
    toggleMultiStreamBtn.addEventListener('click', async () => {
        if (!currentRoom) return;
        const moreOptions = document.getElementById('moreOptionsMenu');
        if (moreOptions) moreOptions.style.display = 'none';

        await loadSubscription();

        // If free tier and not admin, prompt subscription upgrade directly!
        if (!currentSubscription.can_multistream && !currentSubscription.is_admin) {
            if (upgradeModal) upgradeModal.style.display = 'flex';
            return;
        }

        if (multiStreamModal) multiStreamModal.style.display = 'flex';
        await loadDestinations();
        await checkRoomStreamingStatus();
    });
}

if (closeMultiStreamModalBtn) {
    closeMultiStreamModalBtn.addEventListener('click', () => {
        if (multiStreamModal) multiStreamModal.style.display = 'none';
    });
}

if (closeUpgradeModalBtn) {
    closeUpgradeModalBtn.addEventListener('click', () => {
        if (upgradeModal) upgradeModal.style.display = 'none';
    });
}

// Subscribe Plan Buttons inside Upgrade Modal
document.querySelectorAll('.subscribe-btn').forEach(btn => {
    btn.addEventListener('click', async () => {
        const plan = btn.getAttribute('data-plan') || 'pro';
        const originalText = btn.textContent;
        btn.textContent = 'Activating...';
        btn.disabled = true;

        try {
            const idToken = await getAuthToken();
            const res = await fetch('/api/user/subscribe', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${idToken}`
                },
                body: JSON.stringify({ plan })
            });

            const data = await res.json();
            if (res.ok && data.status === 'success') {
                showToast(`🎉 ${data.message || 'Subscription Activated!'}`);
                if (upgradeModal) upgradeModal.style.display = 'none';
                currentSubscription = data.subscription;
                updateSubscriptionUI();
                if (multiStreamModal) multiStreamModal.style.display = 'flex';
                await loadDestinations();
            } else {
                showToast(data.detail || "Activation failed", true);
            }
        } catch (e) {
            console.error("Subscription error:", e);
            showToast("Failed to activate subscription. Check connection.", true);
        } finally {
            btn.textContent = originalText;
            btn.disabled = false;
        }
    });
});

if (addNewDestinationBtn) {
    addNewDestinationBtn.addEventListener('click', () => {
        if (newDestForm) {
            newDestForm.style.display = 'block';
            destPlatformSelect.value = 'youtube';
            destUrlInput.value = PLATFORM_PRESETS.youtube.url;
            destNameInput.value = 'YouTube Live';
            destKeyInput.value = '';
        }
    });
}

if (cancelDestBtn) {
    cancelDestBtn.addEventListener('click', () => {
        if (newDestForm) newDestForm.style.display = 'none';
    });
}

if (saveDestBtn) {
    saveDestBtn.addEventListener('click', async () => {
        const platform = destPlatformSelect.value;
        const name = destNameInput.value.trim() || 'Live Channel';
        const url = destUrlInput.value.trim();
        const key = destKeyInput.value.trim();

        if (!url) {
            showToast("Please provide the RTMP Ingest URL.", true);
            return;
        }
        if (!key) {
            showToast("Please enter your Stream Key.", true);
            return;
        }

        const newTarget = {
            id: `dest_${Date.now()}`,
            platform,
            name,
            server_url: url,
            stream_key: key,
            enabled: true
        };

        currentDestinations.push(newTarget);
        await saveDestinationsToBackend();
        renderDestinations();
        if (newDestForm) newDestForm.style.display = 'none';
        showToast("Destination saved!");
    });
}

if (startMultiStreamBtn) {
    startMultiStreamBtn.addEventListener('click', async () => {
        if (!currentRoom) return;

        const enabledTargets = currentDestinations.filter(d => d.enabled !== false);
        if (enabledTargets.length === 0) {
            showToast("Please enable or add at least one destination first.", true);
            return;
        }

        // Build full RTMP destination URLs with stream keys
        const rtmpUrls = enabledTargets.map(t => {
            let sUrl = t.server_url.trim();
            if (!sUrl.endsWith('/')) sUrl += '/';
            return `${sUrl}${t.stream_key.trim()}`;
        });

        const selectedLayout = document.querySelector('input[name="streamLayout"]:checked')?.value || 'speaker';

        startMultiStreamBtn.disabled = true;
        startMultiStreamBtn.innerHTML = '<span class="material-symbols-outlined spinning">progress_activity</span> Starting Broadcast...';

        try {
            const idToken = await getAuthToken();
            const res = await fetch('/api/streaming/start', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${idToken}`
                },
                body: JSON.stringify({
                    room_id: currentRoom.name,
                    rtmp_urls: rtmpUrls,
                    layout: selectedLayout
                })
            });

            const data = await res.json();
            if (res.ok && data.status === 'success') {
                activeStreamEgressId = data.egress_id;
                showActiveStreamUI(rtmpUrls.length);
                showToast(`🔴 Broadcasting live to ${rtmpUrls.length} destination(s)!`);
            } else if (res.status === 403) {
                if (multiStreamModal) multiStreamModal.style.display = 'none';
                if (upgradeModal) upgradeModal.style.display = 'flex';
                showToast(data.detail || "Subscription required", true);
            } else {
                showToast(data.detail || "Failed to initiate multi-streaming.", true);
            }
        } catch (e) {
            console.error("Multi-stream start error:", e);
            showToast("Failed to connect to streaming service.", true);
        } finally {
            startMultiStreamBtn.disabled = false;
            startMultiStreamBtn.innerHTML = '<span class="material-symbols-outlined">podcasts</span> Go Live to Selected Platforms';
        }
    });
}

if (stopActiveMultiStreamBtn) {
    stopActiveMultiStreamBtn.addEventListener('click', async () => {
        if (!currentRoom) return;
        stopActiveMultiStreamBtn.disabled = true;
        stopActiveMultiStreamBtn.textContent = 'Stopping...';

        try {
            const idToken = await getAuthToken();
            const res = await fetch('/api/streaming/stop', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${idToken}`
                },
                body: JSON.stringify({
                    room_id: currentRoom.name,
                    egress_id: activeStreamEgressId
                })
            });

            if (res.ok) {
                activeStreamEgressId = null;
                hideActiveStreamUI();
                showToast("Multi-Stream broadcast ended.");
            } else {
                showToast("Failed to stop stream.", true);
            }
        } catch (e) {
            console.error("Stop stream error:", e);
            showToast("Failed to stop multi-stream.", true);
        } finally {
            stopActiveMultiStreamBtn.disabled = false;
            stopActiveMultiStreamBtn.textContent = 'Stop Broadcast';
        }
    });
}

// --- Media Controls ---
if (toggleMicBtn) {
    toggleMicBtn.addEventListener('click', async () => {
        if (!currentRoom) return;
        isMicEnabled = !isMicEnabled;
        await currentRoom.localParticipant.setMicrophoneEnabled(isMicEnabled);
        toggleMicBtn.classList.toggle('active', isMicEnabled);
        const icon = toggleMicBtn.querySelector('.material-symbols-outlined');
        const text = toggleMicBtn.querySelector('.btn-text');
        icon.textContent = isMicEnabled ? 'mic' : 'mic_off';
        if (text) text.textContent = isMicEnabled ? 'Mute' : 'Unmute';
    });
}

if (toggleVideoBtn) {
    toggleVideoBtn.addEventListener('click', async () => {
        if (!currentRoom) return;
        isVideoEnabled = !isVideoEnabled;
        await currentRoom.localParticipant.setCameraEnabled(isVideoEnabled);
        toggleVideoBtn.classList.toggle('active', isVideoEnabled);
        const icon = toggleVideoBtn.querySelector('.material-symbols-outlined');
        const text = toggleVideoBtn.querySelector('.btn-text');
        icon.textContent = isVideoEnabled ? 'videocam' : 'videocam_off';
        if (text) text.textContent = isVideoEnabled ? 'Hide' : 'Show';
        
        const localWrapper = document.getElementById('wrapper-local-camera');
        if (localWrapper) localWrapper.classList.toggle('video-muted', !isVideoEnabled);
    });
}

async function updateCameraDevicesList() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) return;
    try {
        const devices = await navigator.mediaDevices.enumerateDevices();
        availableVideoDevices = devices.filter(d => d.kind === 'videoinput');
        
        // Preserve user's existing selection if still present in available devices
        const isCurrentDeviceStillAvailable = availableVideoDevices.some(d => d.deviceId === activeCameraDeviceId);
        
        if (!isCurrentDeviceStillAvailable) {
            if (currentRoom && currentRoom.localParticipant) {
                const pub = currentRoom.localParticipant.getTrackPublication(Track.Source.Camera);
                const mediaStreamTrack = pub?.videoTrack?.mediaStreamTrack;
                if (mediaStreamTrack && typeof mediaStreamTrack.getSettings === 'function') {
                    const settings = mediaStreamTrack.getSettings();
                    if (settings && settings.deviceId) {
                        activeCameraDeviceId = settings.deviceId;
                    }
                }
            }
            if (!activeCameraDeviceId && availableVideoDevices.length > 0) {
                const savedPref = localStorage.getItem('preferred_camera_id');
                const matchedPref = savedPref && availableVideoDevices.find(d => d.deviceId === savedPref);
                activeCameraDeviceId = matchedPref ? matchedPref.deviceId : availableVideoDevices[0].deviceId;
            }
        }

        if (flipCameraBtn) {
            if (availableVideoDevices.length > 0) {
                flipCameraBtn.style.display = 'flex';
                if (flipCameraBtnText) {
                    flipCameraBtnText.textContent = availableVideoDevices.length > 1 ? 'Switch Camera' : 'Camera Options';
                }
            } else {
                flipCameraBtn.style.display = 'none';
            }
        }

        if (cameraListContainer) {
            const wasOpen = cameraListContainer.style.display === 'flex';
            if (availableVideoDevices.length > 0) {
                cameraListContainer.innerHTML = '';
                availableVideoDevices.forEach((device, idx) => {
                    const label = device.label || `Camera ${idx + 1}`;
                    const isCurrent = device.deviceId === activeCameraDeviceId;
                    const item = document.createElement('button');
                    item.className = 'camera-item' + (isCurrent ? ' active' : '');
                    item.type = 'button';
                    
                    const iconSpan = document.createElement('span');
                    iconSpan.className = 'material-symbols-outlined';
                    iconSpan.textContent = isCurrent ? 'check_circle' : 'videocam';
                    
                    const textSpan = document.createElement('span');
                    textSpan.style.flex = '1';
                    textSpan.style.overflow = 'hidden';
                    textSpan.style.textOverflow = 'ellipsis';
                    textSpan.style.whiteSpace = 'nowrap';
                    textSpan.textContent = label;
                    
                    item.appendChild(iconSpan);
                    item.appendChild(textSpan);
                    
                    item.addEventListener('click', async (e) => {
                        e.stopPropagation();
                        await selectCameraDevice(device.deviceId);
                    });
                    
                    cameraListContainer.appendChild(item);
                });
                cameraListContainer.style.display = wasOpen ? 'flex' : 'none';
            } else {
                cameraListContainer.style.display = 'none';
                cameraListContainer.innerHTML = '';
            }
        }
    } catch (err) {
        console.warn("Could not enumerate media devices:", err);
    }
}

async function selectCameraDevice(targetDeviceId) {
    if (!currentRoom) return;
    try {
        activeCameraDeviceId = targetDeviceId;
        try { localStorage.setItem('preferred_camera_id', targetDeviceId); } catch(e) {}
        
        let switchSucceeded = false;
        if (typeof currentRoom.switchActiveDevice === 'function') {
            try {
                await currentRoom.switchActiveDevice('videoinput', targetDeviceId);
                switchSucceeded = true;
            } catch (swErr) {
                console.warn("switchActiveDevice failed, falling back to camera toggle:", swErr);
            }
        }
        
        if (!switchSucceeded && currentRoom.localParticipant) {
            await currentRoom.localParticipant.setCameraEnabled(false);
            await new Promise(r => setTimeout(r, 250));
            await currentRoom.localParticipant.setCameraEnabled(true, {
                deviceId: targetDeviceId
            });
        }

        const pub = currentRoom.localParticipant.getTrackPublication(Track.Source.Camera);
        if (pub && pub.videoTrack) {
            const localVideoElement = document.getElementById('localVideo');
            if (localVideoElement) {
                pub.videoTrack.attach(localVideoElement);
            }
            const wrapperVideo = document.querySelector('#wrapper-local-camera video');
            if (wrapperVideo && wrapperVideo !== localVideoElement) {
                pub.videoTrack.attach(wrapperVideo);
            }
        }

        if (backgroundProcessor) {
            try {
                const videoTrack = currentRoom.localParticipant.getTrackPublication(Track.Source.Camera)?.videoTrack;
                if (videoTrack) {
                    await videoTrack.setProcessor(backgroundProcessor);
                }
            } catch (procErr) {
                console.warn("Background processor skipped for device:", procErr);
            }
        }

        await updateCameraDevicesList();

        const selectedDevice = availableVideoDevices.find(d => d.deviceId === targetDeviceId);
        const label = selectedDevice ? (selectedDevice.label || 'Camera') : 'Camera';
        showToast(`Switched camera to: ${label}`);
    } catch (err) {
        console.error("Error switching camera device:", err);
        showToast("Could not switch camera: " + (err.message || "Unknown error"), true);
    }
}

let _deviceChangeTimer = null;
if (navigator.mediaDevices && navigator.mediaDevices.addEventListener) {
    navigator.mediaDevices.addEventListener('devicechange', () => {
        if (_deviceChangeTimer) clearTimeout(_deviceChangeTimer);
        _deviceChangeTimer = setTimeout(() => {
            updateCameraDevicesList();
            updateAudioDevicesList();
        }, 800);
    });
}

async function updateAudioDevicesList() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) return;
    try {
        const devices = await navigator.mediaDevices.enumerateDevices();
        availableAudioInputDevices = devices.filter(d => d.kind === 'audioinput');
        availableAudioOutputDevices = devices.filter(d => d.kind === 'audiooutput');

        // Microphone input devices
        const isCurrentMicStillAvailable = availableAudioInputDevices.some(d => d.deviceId === activeAudioInputDeviceId);
        if (!isCurrentMicStillAvailable) {
            if (currentRoom && currentRoom.localParticipant) {
                const pub = currentRoom.localParticipant.getTrackPublication(Track.Source.Microphone);
                const mediaStreamTrack = pub?.audioTrack?.mediaStreamTrack;
                if (mediaStreamTrack && typeof mediaStreamTrack.getSettings === 'function') {
                    const settings = mediaStreamTrack.getSettings();
                    if (settings && settings.deviceId) {
                        activeAudioInputDeviceId = settings.deviceId;
                    }
                }
            }
            if (!activeAudioInputDeviceId && availableAudioInputDevices.length > 0) {
                const savedPref = localStorage.getItem('preferred_mic_id');
                const matchedPref = savedPref && availableAudioInputDevices.find(d => d.deviceId === savedPref);
                activeAudioInputDeviceId = matchedPref ? matchedPref.deviceId : availableAudioInputDevices[0].deviceId;
            }
        }

        if (audioDevicesBtn) {
            if (availableAudioInputDevices.length > 0) {
                audioDevicesBtn.style.display = 'flex';
            } else {
                audioDevicesBtn.style.display = 'none';
            }
        }

        if (audioListContainer) {
            const wasOpen = audioListContainer.style.display === 'flex';
            if (availableAudioInputDevices.length > 0) {
                audioListContainer.innerHTML = '';
                availableAudioInputDevices.forEach((device, idx) => {
                    const label = device.label || `Microphone ${idx + 1}`;
                    const isCurrent = device.deviceId === activeAudioInputDeviceId;
                    const item = document.createElement('button');
                    item.className = 'camera-item' + (isCurrent ? ' active' : '');
                    item.type = 'button';

                    const iconSpan = document.createElement('span');
                    iconSpan.className = 'material-symbols-outlined';
                    iconSpan.textContent = isCurrent ? 'check_circle' : 'mic';

                    const textSpan = document.createElement('span');
                    textSpan.style.flex = '1';
                    textSpan.style.overflow = 'hidden';
                    textSpan.style.textOverflow = 'ellipsis';
                    textSpan.style.whiteSpace = 'nowrap';
                    textSpan.textContent = label;

                    item.appendChild(iconSpan);
                    item.appendChild(textSpan);

                    item.addEventListener('click', async (e) => {
                        e.stopPropagation();
                        await selectAudioInputDevice(device.deviceId);
                    });

                    audioListContainer.appendChild(item);
                });
                audioListContainer.style.display = wasOpen ? 'flex' : 'none';
            } else {
                audioListContainer.style.display = 'none';
                audioListContainer.innerHTML = '';
            }
        }

        // Speaker / Output devices (if supported by browser)
        if (speakerDevicesBtn && speakerListContainer) {
            const wasOpen = speakerListContainer.style.display === 'flex';
            if (availableAudioOutputDevices.length > 0 && 'setSinkId' in HTMLMediaElement.prototype) {
                speakerDevicesBtn.style.display = 'flex';
                speakerListContainer.innerHTML = '';
                availableAudioOutputDevices.forEach((device, idx) => {
                    const label = device.label || `Speaker ${idx + 1}`;
                    const isCurrent = device.deviceId === activeAudioOutputDeviceId;
                    const item = document.createElement('button');
                    item.className = 'camera-item' + (isCurrent ? ' active' : '');
                    item.type = 'button';

                    const iconSpan = document.createElement('span');
                    iconSpan.className = 'material-symbols-outlined';
                    iconSpan.textContent = isCurrent ? 'check_circle' : 'volume_up';

                    const textSpan = document.createElement('span');
                    textSpan.style.flex = '1';
                    textSpan.style.overflow = 'hidden';
                    textSpan.style.textOverflow = 'ellipsis';
                    textSpan.style.whiteSpace = 'nowrap';
                    textSpan.textContent = label;

                    item.appendChild(iconSpan);
                    item.appendChild(textSpan);

                    item.addEventListener('click', async (e) => {
                        e.stopPropagation();
                        await selectAudioOutputDevice(device.deviceId);
                    });

                    speakerListContainer.appendChild(item);
                });
                speakerListContainer.style.display = wasOpen ? 'flex' : 'none';
            } else {
                speakerDevicesBtn.style.display = 'none';
                speakerListContainer.style.display = 'none';
            }
        }
    } catch (err) {
        console.warn("Could not enumerate audio devices:", err);
    }
}

async function selectAudioInputDevice(targetDeviceId) {
    if (!currentRoom) return;
    try {
        activeAudioInputDeviceId = targetDeviceId;
        try { localStorage.setItem('preferred_mic_id', targetDeviceId); } catch(e) {}

        let switchSucceeded = false;
        if (typeof currentRoom.switchActiveDevice === 'function') {
            try {
                await currentRoom.switchActiveDevice('audioinput', targetDeviceId);
                switchSucceeded = true;
            } catch (swErr) {
                console.warn("switchActiveDevice audioinput failed, falling back to mic toggle:", swErr);
            }
        }

        if (!switchSucceeded && currentRoom.localParticipant) {
            const wasEnabled = isMicEnabled;
            await currentRoom.localParticipant.setMicrophoneEnabled(false);
            if (wasEnabled) {
                await new Promise(r => setTimeout(r, 200));
                await currentRoom.localParticipant.setMicrophoneEnabled(true, {
                    deviceId: targetDeviceId
                });
            }
        }

        await updateAudioDevicesList();

        const selectedDevice = availableAudioInputDevices.find(d => d.deviceId === targetDeviceId);
        const label = selectedDevice ? (selectedDevice.label || 'Microphone') : 'Microphone';
        showToast(`Switched microphone to: ${label}`);
    } catch (err) {
        console.error("Error switching audio input:", err);
        showToast("Could not switch microphone: " + (err.message || "Unknown error"), true);
    }
}

async function selectAudioOutputDevice(targetDeviceId) {
    if (!currentRoom) return;
    try {
        activeAudioOutputDeviceId = targetDeviceId;
        try { localStorage.setItem('preferred_speaker_id', targetDeviceId); } catch(e) {}

        if (typeof currentRoom.switchActiveDevice === 'function') {
            await currentRoom.switchActiveDevice('audiooutput', targetDeviceId);
        }

        document.querySelectorAll('audio, video').forEach(el => {
            if (typeof el.setSinkId === 'function') {
                el.setSinkId(targetDeviceId).catch(e => console.warn("Failed setSinkId on element:", e));
            }
        });

        await updateAudioDevicesList();

        const selectedDevice = availableAudioOutputDevices.find(d => d.deviceId === targetDeviceId);
        const label = selectedDevice ? (selectedDevice.label || 'Speaker') : 'Speaker';
        showToast(`Switched speaker to: ${label}`);
    } catch (err) {
        console.error("Error switching audio output:", err);
        showToast("Could not switch speaker: " + (err.message || "Unknown error"), true);
    }
}

function _toggleAccordion(btn, container) {
    if (!container) return;
    const isClosed = container.style.display === 'none' || !container.style.display;
    container.style.display = isClosed ? 'flex' : 'none';
    const arrow = btn ? btn.querySelector('.accordion-arrow') : null;
    if (arrow) {
        arrow.textContent = isClosed ? 'expand_less' : 'expand_more';
    }
}

if (flipCameraBtn) {
    flipCameraBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        _toggleAccordion(flipCameraBtn, cameraListContainer);
    });
}

if (audioDevicesBtn) {
    audioDevicesBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        _toggleAccordion(audioDevicesBtn, audioListContainer);
    });
}

if (speakerDevicesBtn) {
    speakerDevicesBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        _toggleAccordion(speakerDevicesBtn, speakerListContainer);
    });
}

if (flipCameraBtn) {
    flipCameraBtn.addEventListener('click', async () => {
        if (!currentRoom) return;
        await updateCameraDevicesList();
        
        if (availableVideoDevices.length === 0) {
            showToast("No camera detected.", true);
            return;
        }

        if (availableVideoDevices.length === 1) {
            const isMobileDevice = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent) || (navigator.maxTouchPoints && navigator.maxTouchPoints > 2);
            if (isMobileDevice) {
                currentFacingMode = currentFacingMode === 'user' ? 'environment' : 'user';
                await currentRoom.localParticipant.setCameraEnabled(false);
                await new Promise(r => setTimeout(r, 400));
                await currentRoom.localParticipant.setCameraEnabled(true, { facingMode: currentFacingMode });
                const pub = currentRoom.localParticipant.getTrackPublication(Track.Source.Camera);
                if (pub && pub.videoTrack) { pub.videoTrack.attach(localVideo); }
                showToast("Flipped camera");
            } else {
                showToast("Only 1 camera detected. Plug in an external camera to switch.", true);
            }
            return;
        }

        let currentIndex = availableVideoDevices.findIndex(d => d.deviceId === activeCameraDeviceId);
        if (currentIndex === -1) currentIndex = 0;
        const nextIndex = (currentIndex + 1) % availableVideoDevices.length;
        const nextDevice = availableVideoDevices[nextIndex];
        
        await selectCameraDevice(nextDevice.deviceId);
    });
}

const isMobileDevice = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent) || (navigator.maxTouchPoints && navigator.maxTouchPoints > 2);
if (isMobileDevice && toggleScreenBtn) { toggleScreenBtn.style.display = 'none'; }

if (toggleScreenBtn) {
    toggleScreenBtn.addEventListener('click', async () => {
        if (!currentRoom) return;
        if (!isScreenSharing) {
            try {
                await currentRoom.localParticipant.setScreenShareEnabled(true);
                isScreenSharing = true;
                toggleScreenBtn.classList.add('active');
                toggleScreenBtn.querySelector('.material-symbols-outlined').textContent = 'cancel_presentation';
                (toggleScreenBtn.querySelector('.btn-text') && (toggleScreenBtn.querySelector('.btn-text').textContent = 'Stop'));
            } catch (err) {
                console.error("Error sharing screen:", err);
                showToast("Could not share screen: " + (err.message || "Not supported on this device."), true);
            }
        } else {
            await currentRoom.localParticipant.setScreenShareEnabled(false);
            isScreenSharing = false;
            toggleScreenBtn.classList.remove('active');
            toggleScreenBtn.querySelector('.material-symbols-outlined').textContent = 'present_to_all';
            (toggleScreenBtn.querySelector('.btn-text') && (toggleScreenBtn.querySelector('.btn-text').textContent = 'Share'));
        }
    });
}

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
    toggleChatBtn.addEventListener('click', () => { toggleSidebar(chatSidebar, toggleChatBtn); });
    if (closeChatBtn) { closeChatBtn.addEventListener('click', () => { closeAllSidebars(); }); }
}

// People sidebar logic
if (togglePeopleBtn) {
    const closePeopleBtn = document.getElementById('closePeopleBtn');
    togglePeopleBtn.addEventListener('click', () => { toggleSidebar(peopleSidebar, togglePeopleBtn); });
    if (closePeopleBtn) { closePeopleBtn.addEventListener('click', () => { closeAllSidebars(); }); }
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
if (sendBtn) sendBtn.addEventListener('click', sendMessage);
if (chatInput) chatInput.addEventListener('keypress', (e) => { if (e.key === 'Enter') sendMessage(); });

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

        const fullscreenBtn = document.createElement('button');
        fullscreenBtn.className = 'fullscreen-overlay-btn';
        fullscreenBtn.title = 'Full Screen';
        fullscreenBtn.innerHTML = '<span class="material-symbols-outlined">fullscreen</span>';
        fullscreenBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            toggleWrapperFullscreen(wrapper);
        });

        wrapper.addEventListener('dblclick', () => toggleWrapperFullscreen(wrapper));
        wrapper.appendChild(label);
        wrapper.appendChild(pinBtn);
        wrapper.appendChild(pipBtn);
        wrapper.appendChild(fullscreenBtn);

        const avatarDiv = document.createElement('div');
        avatarDiv.className = 'avatar-placeholder';
        avatarDiv.textContent = (participant.name || participant.identity || '?').charAt(0).toUpperCase();
        wrapper.appendChild(avatarDiv);

        if (track.isMuted) {
            wrapper.classList.add('video-muted');
        }

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

function isElementFullscreen(el) {
    return document.fullscreenElement === el ||
           document.webkitFullscreenElement === el ||
           document.mozFullScreenElement === el ||
           document.msFullscreenElement === el;
}

function toggleWrapperFullscreen(wrapper) {
    if (!wrapper) return;
    if (isElementFullscreen(wrapper)) {
        if (document.exitFullscreen) {
            document.exitFullscreen().catch(err => console.error('Exit fullscreen error:', err));
        } else if (document.webkitExitFullscreen) {
            document.webkitExitFullscreen();
        } else if (document.mozCancelFullScreen) {
            document.mozCancelFullScreen();
        } else if (document.msExitFullscreen) {
            document.msExitFullscreen();
        }
    } else {
        if (wrapper.requestFullscreen) {
            wrapper.requestFullscreen().catch(err => {
                console.warn('Standard fullscreen failed, attempting video fallback:', err);
                const video = wrapper.querySelector('video');
                if (video && video.webkitEnterFullscreen) video.webkitEnterFullscreen();
            });
        } else if (wrapper.webkitRequestFullscreen) {
            wrapper.webkitRequestFullscreen();
        } else if (wrapper.mozRequestFullScreen) {
            wrapper.mozRequestFullScreen();
        } else if (wrapper.msRequestFullscreen) {
            wrapper.msRequestFullscreen();
        } else {
            const video = wrapper.querySelector('video');
            if (video && video.webkitEnterFullscreen) {
                video.webkitEnterFullscreen();
            }
        }
    }
}

function toggleAppFullscreen() {
    const fsEl = document.fullscreenElement || document.webkitFullscreenElement || document.mozFullScreenElement || document.msFullscreenElement;
    if (fsEl) {
        if (document.exitFullscreen) {
            document.exitFullscreen().catch(err => console.error('Exit fullscreen error:', err));
        } else if (document.webkitExitFullscreen) {
            document.webkitExitFullscreen();
        } else if (document.mozCancelFullScreen) {
            document.mozCancelFullScreen();
        } else if (document.msExitFullscreen) {
            document.msExitFullscreen();
        }
    } else {
        const docEl = document.documentElement;
        if (docEl.requestFullscreen) {
            docEl.requestFullscreen().catch(err => console.error('Request fullscreen error:', err));
        } else if (docEl.webkitRequestFullscreen) {
            docEl.webkitRequestFullscreen();
        } else if (docEl.mozRequestFullScreen) {
            docEl.mozRequestFullScreen();
        } else if (docEl.msRequestFullscreen) {
            docEl.msRequestFullscreen();
        }
    }
}

function handleFullscreenChange() {
    const fsEl = document.fullscreenElement || document.webkitFullscreenElement || document.mozFullScreenElement || document.msFullscreenElement;
    
    document.querySelectorAll('.video-wrapper').forEach(wrapper => {
        const isFs = (wrapper === fsEl);
        wrapper.classList.toggle('is-fullscreen', isFs);
        const fsBtn = wrapper.querySelector('.fullscreen-overlay-btn');
        if (fsBtn) {
            fsBtn.title = isFs ? 'Exit Full Screen' : 'Full Screen';
            fsBtn.innerHTML = `<span class="material-symbols-outlined">${isFs ? 'fullscreen_exit' : 'fullscreen'}</span>`;
        }
    });

    const appFsBtn = document.getElementById('toggleAppFullscreenBtn');
    if (appFsBtn) {
        const isAppFs = (fsEl === document.documentElement || fsEl === document.body);
        appFsBtn.innerHTML = `<span class="material-symbols-outlined">${isAppFs ? 'fullscreen_exit' : 'fullscreen'}</span> ${isAppFs ? 'Exit Fullscreen' : 'Fullscreen Mode'}`;
    }
}

document.addEventListener('fullscreenchange', handleFullscreenChange);
document.addEventListener('webkitfullscreenchange', handleFullscreenChange);
document.addEventListener('mozfullscreenchange', handleFullscreenChange);
document.addEventListener('MSFullscreenChange', handleFullscreenChange);

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
    localWrapper.addEventListener('dblclick', () => toggleWrapperFullscreen(localWrapper));
    const pinBtn = localWrapper.querySelector('.pin-overlay-btn');
    if (pinBtn) {
        pinBtn.addEventListener('click', (e) => { e.stopPropagation(); togglePin(localWrapper.id); });
    }
    const pipBtn = localWrapper.querySelector('.pip-overlay-btn');
    if (pipBtn) {
        pipBtn.addEventListener('click', async (e) => {
            e.stopPropagation();
            const videoElement = localWrapper.querySelector('video');
            if (videoElement) {
                if (document.pictureInPictureElement) { await document.exitPictureInPicture(); }
                else if (videoElement.requestPictureInPicture) { await videoElement.requestPictureInPicture(); }
            }
        });
    }
    const fullscreenBtn = localWrapper.querySelector('.fullscreen-overlay-btn');
    if (fullscreenBtn) {
        fullscreenBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            toggleWrapperFullscreen(localWrapper);
        });
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
            (toggleRecordBtn.querySelector('.btn-text') && (toggleRecordBtn.querySelector('.btn-text').textContent = 'Stop Rec'));
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
        (toggleRecordBtn.querySelector('.btn-text') && (toggleRecordBtn.querySelector('.btn-text').textContent = 'Record'));
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
        toggleHandBtn.classList.toggle('active', isHandRaised);
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

const mobileWhiteboardCloseBtn = document.getElementById('mobileWhiteboardCloseBtn');
if (mobileWhiteboardCloseBtn) {
    mobileWhiteboardCloseBtn.addEventListener('click', () => {
        isWhiteboardActive = false;
        if (toggleWhiteboardBtn) toggleWhiteboardBtn.classList.remove('active');
        mainColumn.classList.remove('with-whiteboard');
        whiteboardContainer.classList.remove('active');
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

if (togglePollsBtn) { togglePollsBtn.addEventListener('click', () => { toggleSidebar(pollQaSidebar, togglePollsBtn); }); }
if (closePollQaBtn) { closePollQaBtn.addEventListener('click', () => { closeAllSidebars(); }); }

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


// ==========================================
// SIDEBAR & MOBILE MENU TOGGLE
// ==========================================

function closeAllSidebars() {
    [chatSidebar, peopleSidebar, pollQaSidebar].forEach(sidebar => {
        if(sidebar) {
            sidebar.classList.remove('active');
            sidebar.classList.remove('show');
            sidebar.classList.remove('open'); // For polls old css
        }
    });
    [toggleChatBtn, togglePeopleBtn, togglePollsBtn].forEach(btn => {
        if(btn) btn.classList.remove('active');
    });
    const rightPanelContainer = document.querySelector('.right-panel-container');
    if(rightPanelContainer) rightPanelContainer.classList.remove('show');
}

function toggleSidebar(sidebar, btn) {
    const rightPanelContainer = document.querySelector('.right-panel-container');
    if (!sidebar || !rightPanelContainer) return;
    
    const isCurrentlyActive = sidebar.classList.contains('active') || sidebar.classList.contains('show') || sidebar.classList.contains('open');
    
    // Close everything first
    closeAllSidebars();
    
    if (!isCurrentlyActive) {
        // Open the requested sidebar
        sidebar.classList.add('active');
        sidebar.classList.add('show');
        sidebar.classList.add('open');
        if(btn) btn.classList.add('active');
        rightPanelContainer.classList.add('show');
        
        // Remove badges
        if (sidebar === chatSidebar) {
            const badge = document.getElementById('chatBadge');
            if (badge) badge.style.display = 'none';
        }
        if (sidebar === pollQaSidebar) {
            if (typeof qaBadge !== 'undefined' && qaBadge) qaBadge.style.display = 'none';
            if (typeof newQaCount !== 'undefined') newQaCount = 0;
            if (typeof isPollQaOpen !== 'undefined') isPollQaOpen = true;
        }
    } else {
        if (sidebar === pollQaSidebar && typeof isPollQaOpen !== 'undefined') isPollQaOpen = false;
    }
}

// Mobile Menu Toggle
const mobileMenuBtn = document.getElementById('mobileMenuBtn');
const leftSidebar = document.querySelector('.left-sidebar');
if (mobileMenuBtn && leftSidebar) {
    mobileMenuBtn.addEventListener('click', () => {
        leftSidebar.classList.toggle('mobile-open');
    });
}


const navQaBtn = document.getElementById('navQaBtn');
if (navQaBtn) {
    navQaBtn.addEventListener('click', () => {
        if (typeof toggleSidebar !== 'undefined' && typeof pollQaSidebar !== 'undefined') {
            toggleSidebar(pollQaSidebar, navQaBtn);
            // Optionally, switch to Q&A tab if such logic exists
            const qaTab = document.getElementById('qaTabBtn');
            if (qaTab) qaTab.click();
        }
    });
}


// ==========================================
// EXTRA MEDIA CONTROLS LOGIC
// ==========================================

const toggleMoreBtn = document.getElementById('toggleMoreBtn');
const moreOptionsMenu = document.getElementById('moreOptionsMenu');
const toggleSettingsMenuBtn = document.getElementById('toggleSettingsMenuBtn');

if (toggleMoreBtn && moreOptionsMenu) {
    toggleMoreBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        if (emojiPopover) emojiPopover.style.display = 'none';
        if (toggleReactBtn) toggleReactBtn.classList.remove('active');

        const isShowing = moreOptionsMenu.style.display === 'block';
        moreOptionsMenu.style.display = isShowing ? 'none' : 'block';
        toggleMoreBtn.classList.toggle('active', !isShowing);
    });

    document.addEventListener('click', (e) => {
        if (!toggleMoreBtn.contains(e.target) && !moreOptionsMenu.contains(e.target)) {
            moreOptionsMenu.style.display = 'none';
            toggleMoreBtn.classList.remove('active');
        }
    });
}

if (toggleSettingsMenuBtn && navSettingsBtn) {
    toggleSettingsMenuBtn.addEventListener('click', () => {
        if (moreOptionsMenu) moreOptionsMenu.style.display = 'none';
        if (toggleMoreBtn) toggleMoreBtn.classList.remove('active');
        navSettingsBtn.click();
    });
}

if (toggleReactBtn && emojiPopover) {
    toggleReactBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        if (moreOptionsMenu) moreOptionsMenu.style.display = 'none';
        if (toggleMoreBtn) toggleMoreBtn.classList.remove('active');

        const isShowing = emojiPopover.style.display === 'flex' || emojiPopover.style.display === 'block';
        emojiPopover.style.display = isShowing ? 'none' : 'flex';
        toggleReactBtn.classList.toggle('active', !isShowing);
    });

    document.addEventListener('click', (e) => {
        if (!toggleReactBtn.contains(e.target) && !emojiPopover.contains(e.target)) {
            emojiPopover.style.display = 'none';
            toggleReactBtn.classList.remove('active');
        }
    });
    
    // Add logic for individual emoji clicks
    emojiPopover.querySelectorAll('.emoji-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            emojiPopover.style.display = 'none';
            toggleReactBtn.classList.remove('active');
            if(typeof showToast !== 'undefined') showToast('Reaction sent: ' + btn.textContent);
        });
    });
}


if (toggleHandBtn) {
    toggleHandBtn.addEventListener('click', () => {
        toggleHandBtn.classList.toggle('active');
        const isRaised = toggleHandBtn.classList.contains('active');
        if(typeof showToast !== 'undefined') showToast(isRaised ? 'Hand raised' : 'Hand lowered');
    });
}

const shareLinkBtn = document.getElementById('shareLinkBtn');
if (shareLinkBtn) {
    shareLinkBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        copyMeetingLink();
        if(moreOptionsMenu) moreOptionsMenu.style.display = 'none';
        if(toggleMoreBtn) toggleMoreBtn.classList.remove('active');
    });
}

const toggleAppFullscreenBtn = document.getElementById('toggleAppFullscreenBtn');
if (toggleAppFullscreenBtn) {
    toggleAppFullscreenBtn.addEventListener('click', () => {
        toggleAppFullscreen();
        if (moreOptionsMenu) moreOptionsMenu.style.display = 'none';
        if (toggleMoreBtn) toggleMoreBtn.classList.remove('active');
    });
}


// Sidebar Collapse Logic
const collapseSidebarBtn = document.getElementById('collapseSidebarBtn');
const leftSidebarEl = document.querySelector('.left-sidebar');
const collapseIcon = document.getElementById('collapseIcon');

if (collapseSidebarBtn && leftSidebarEl) {
    collapseSidebarBtn.addEventListener('click', () => {
        leftSidebarEl.classList.toggle('icon-only');
        const isCollapsed = leftSidebarEl.classList.contains('icon-only');
        if (collapseIcon) {
            collapseIcon.textContent = isCollapsed ? 'keyboard_double_arrow_right' : 'keyboard_double_arrow_left';
        }
        // Save preference in localStorage
        localStorage.setItem('sidebarCollapsed', isCollapsed);
    });
    
    // Check initial state
    if (localStorage.getItem('sidebarCollapsed') === 'true') {
        leftSidebarEl.classList.add('icon-only');
        if (collapseIcon) collapseIcon.textContent = 'keyboard_double_arrow_right';
    }
}

// ==========================================
// MEETING SETTINGS MODAL LOGIC
// ==========================================
const navSettingsBtn = document.getElementById('navSettingsBtn');
const settingsModal = document.getElementById('settingsModal');
const closeSettingsModalBtn = document.getElementById('closeSettingsModalBtn');
const settingsAudioInputSelect = document.getElementById('settingsAudioInputSelect');
const settingsAudioOutputSelect = document.getElementById('settingsAudioOutputSelect');
const settingsVideoInputSelect = document.getElementById('settingsVideoInputSelect');
const settingsNoiseToggleBtn = document.getElementById('settingsNoiseToggleBtn');
const settingsFlipCamBtn = document.getElementById('settingsFlipCamBtn');
const settingsOpenEffectsBtn = document.getElementById('settingsOpenEffectsBtn');
const settingsDataSaverToggleBtn = document.getElementById('settingsDataSaverToggleBtn');
const settingsCopyLinkBtn = document.getElementById('settingsCopyLinkBtn');

function populateSettingsDevices() {
    // Populate Microphones
    if (settingsAudioInputSelect) {
        settingsAudioInputSelect.innerHTML = '';
        if (availableAudioInputDevices.length > 0) {
            availableAudioInputDevices.forEach((device, idx) => {
                const opt = document.createElement('option');
                opt.value = device.deviceId;
                opt.textContent = device.label || `Microphone ${idx + 1}`;
                if (device.deviceId === activeAudioInputDeviceId) opt.selected = true;
                settingsAudioInputSelect.appendChild(opt);
            });
        } else {
            const opt = document.createElement('option');
            opt.value = '';
            opt.textContent = 'Default Microphone';
            settingsAudioInputSelect.appendChild(opt);
        }
    }

    // Populate Speakers
    if (settingsAudioOutputSelect) {
        settingsAudioOutputSelect.innerHTML = '';
        if (availableAudioOutputDevices.length > 0 && 'setSinkId' in HTMLMediaElement.prototype) {
            availableAudioOutputDevices.forEach((device, idx) => {
                const opt = document.createElement('option');
                opt.value = device.deviceId;
                opt.textContent = device.label || `Speaker ${idx + 1}`;
                if (device.deviceId === activeAudioOutputDeviceId) opt.selected = true;
                settingsAudioOutputSelect.appendChild(opt);
            });
        } else {
            const opt = document.createElement('option');
            opt.value = '';
            opt.textContent = 'System Default Output';
            settingsAudioOutputSelect.appendChild(opt);
        }
    }

    // Populate Cameras
    if (settingsVideoInputSelect) {
        settingsVideoInputSelect.innerHTML = '';
        if (availableVideoDevices.length > 0) {
            availableVideoDevices.forEach((device, idx) => {
                const opt = document.createElement('option');
                opt.value = device.deviceId;
                opt.textContent = device.label || `Camera ${idx + 1}`;
                if (device.deviceId === activeCameraDeviceId) opt.selected = true;
                settingsVideoInputSelect.appendChild(opt);
            });
        } else {
            const opt = document.createElement('option');
            opt.value = '';
            opt.textContent = 'Default Camera';
            settingsVideoInputSelect.appendChild(opt);
        }
    }

    // Update status buttons text
    if (settingsNoiseToggleBtn) {
        settingsNoiseToggleBtn.textContent = isNoiseCancellationEnabled ? 'Enabled' : 'Disabled';
        settingsNoiseToggleBtn.style.color = isNoiseCancellationEnabled ? '#10b981' : 'white';
    }
    if (settingsDataSaverToggleBtn) {
        const isDataSaver = document.body.classList.contains('data-saver-active');
        settingsDataSaverToggleBtn.textContent = isDataSaver ? 'Enabled' : 'Disabled';
        settingsDataSaverToggleBtn.style.color = isDataSaver ? '#10b981' : 'white';
    }
}

if (settingsAudioInputSelect) {
    settingsAudioInputSelect.addEventListener('change', async (e) => {
        if (e.target.value) {
            await selectAudioInputDevice(e.target.value);
        }
    });
}

if (settingsAudioOutputSelect) {
    settingsAudioOutputSelect.addEventListener('change', async (e) => {
        if (e.target.value) {
            await selectAudioOutputDevice(e.target.value);
        }
    });
}

if (settingsVideoInputSelect) {
    settingsVideoInputSelect.addEventListener('change', async (e) => {
        if (e.target.value) {
            await selectCameraDevice(e.target.value);
        }
    });
}

if (navSettingsBtn && settingsModal) {
    navSettingsBtn.addEventListener('click', async () => {
        if (typeof updateCameraDevicesList === 'function') await updateCameraDevicesList();
        if (typeof updateAudioDevicesList === 'function') await updateAudioDevicesList();
        populateSettingsDevices();
        settingsModal.style.display = 'flex';
    });
}

if (closeSettingsModalBtn && settingsModal) {
    closeSettingsModalBtn.addEventListener('click', () => {
        settingsModal.style.display = 'none';
    });
}

// Settings Tabs Switching
const settingsTabBtns = document.querySelectorAll('.settings-tab-btn');
settingsTabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
        settingsTabBtns.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        const tab = btn.getAttribute('data-tab');
        document.querySelectorAll('.settings-tab-pane').forEach(pane => {
            pane.style.display = pane.id === `tab-${tab}` ? 'block' : 'none';
        });
    });
});

// Settings Quick Actions
if (settingsNoiseToggleBtn && toggleNoiseBtn) {
    settingsNoiseToggleBtn.addEventListener('click', () => {
        toggleNoiseBtn.click();
        setTimeout(populateSettingsDevices, 100);
    });
}

if (settingsFlipCamBtn && flipCameraBtn) {
    settingsFlipCamBtn.addEventListener('click', () => {
        flipCameraBtn.click();
        setTimeout(populateSettingsDevices, 500);
    });
}

if (settingsOpenEffectsBtn && effectsModal && settingsModal) {
    settingsOpenEffectsBtn.addEventListener('click', () => {
        settingsModal.style.display = 'none';
        effectsModal.style.display = 'flex';
    });
}

if (settingsDataSaverToggleBtn && toggleDataSaverBtn) {
    settingsDataSaverToggleBtn.addEventListener('click', () => {
        toggleDataSaverBtn.click();
        setTimeout(populateSettingsDevices, 100);
    });
}

if (settingsCopyLinkBtn) {
    settingsCopyLinkBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        copyMeetingLink();
    });
}

// Polls & Q&A Logic
const showCreatePollBtn = document.getElementById('showCreatePollBtn');
const pollEmptyState = document.getElementById('pollEmptyState');
const pollCreateSection = document.getElementById('pollCreateSection');

if (showCreatePollBtn && pollEmptyState && pollCreateSection) {
    showCreatePollBtn.addEventListener('click', () => {
        pollEmptyState.style.display = 'none';
        pollCreateSection.style.display = 'block';
    });
}

// Tab Switching
const tabPolls = document.getElementById('tabPolls');
const tabQA = document.getElementById('tabQA');
const tabContentPolls = document.getElementById('tabContentPolls');
const tabContentQA = document.getElementById('tabContentQA');

if (tabPolls && tabQA && tabContentPolls && tabContentQA) {
    tabPolls.addEventListener('click', () => {
        tabPolls.classList.add('active');
        tabQA.classList.remove('active');
        tabContentPolls.style.display = 'block';
        tabContentQA.style.display = 'none';
    });
    tabQA.addEventListener('click', () => {
        tabQA.classList.add('active');
        tabPolls.classList.remove('active');
        tabContentQA.style.display = 'block';
        tabContentPolls.style.display = 'none';
    });
}

// ==========================================
// USER SUPPORT MODAL LOGIC
// ==========================================
const openSupportBtn = document.getElementById('openSupportBtn');
const supportModal = document.getElementById('supportModal');
const closeSupportModalBtn = document.getElementById('closeSupportModalBtn');
const userSupportForm = document.getElementById('userSupportForm');
const userSupportCategory = document.getElementById('userSupportCategory');
const userSupportSubject = document.getElementById('userSupportSubject');
const userSupportMessage = document.getElementById('userSupportMessage');
const userSupportAlert = document.getElementById('userSupportAlert');
const userSupportSubmitBtn = document.getElementById('userSupportSubmitBtn');

if (openSupportBtn && supportModal) {
    openSupportBtn.addEventListener('click', () => {
        userSupportAlert.style.display = 'none';
        supportModal.style.display = 'flex';
    });

    closeSupportModalBtn.addEventListener('click', () => {
        supportModal.style.display = 'none';
    });

    supportModal.addEventListener('click', (e) => {
        if (e.target === supportModal) {
            supportModal.style.display = 'none';
        }
    });

    userSupportForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        
        userSupportSubmitBtn.disabled = true;
        userSupportSubmitBtn.innerHTML = `<span class="material-symbols-outlined spin-icon">sync</span> Submitting...`;
        userSupportAlert.style.display = 'none';

        try {
            const token = await getAuthToken();
            if (!token) {
                userSupportAlert.style.background = 'rgba(255, 85, 85, 0.15)';
                userSupportAlert.style.color = '#ff5555';
                userSupportAlert.style.border = '1px solid #ff5555';
                userSupportAlert.textContent = 'Please log in or create a free account to submit a support ticket.';
                userSupportAlert.style.display = 'block';
                return;
            }

            const res = await fetch('/api/support/tickets', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${token}`
                },
                body: JSON.stringify({
                    category: userSupportCategory.value,
                    subject: userSupportSubject.value.trim(),
                    message: userSupportMessage.value.trim()
                })
            });

            const data = await res.json();
            if (!res.ok) {
                throw new Error(data.detail || 'Failed to submit ticket');
            }

            userSupportAlert.style.background = 'rgba(0, 255, 163, 0.15)';
            userSupportAlert.style.color = '#00ffa3';
            userSupportAlert.style.border = '1px solid #00ffa3';
            userSupportAlert.innerHTML = `🎉 <strong>Ticket #${data.ticket_id} Created!</strong> Our team will review and reply to your email shortly.`;
            userSupportAlert.style.display = 'block';

            userSupportSubject.value = '';
            userSupportMessage.value = '';

            setTimeout(() => {
                supportModal.style.display = 'none';
            }, 3500);
        } catch (err) {
            userSupportAlert.style.background = 'rgba(255, 85, 85, 0.15)';
            userSupportAlert.style.color = '#ff5555';
            userSupportAlert.style.border = '1px solid #ff5555';
            userSupportAlert.textContent = `Error: ${err.message}`;
            userSupportAlert.style.display = 'block';
        } finally {
            userSupportSubmitBtn.disabled = false;
            userSupportSubmitBtn.innerHTML = `<span class="material-symbols-outlined">send</span> Submit Support Ticket`;
        }
    });
}

