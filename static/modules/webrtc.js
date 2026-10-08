// ==========================================
// WEBRTC CALL ENGINE & PARTICIPANT MANAGEMENT
// ==========================================
import { state } from "./state.js";
import { showToast, copyMeetingLink, formatFriendlyErrorMessage } from "./utils.js";
import { updateCameraDevicesList, updateAudioDevicesList, updateAudioOutputButtonState, toggleDataSaverMode, updateDataSaverBanner } from "./devices.js";
import { handleIncomingCaption, stopSpeechRecognition, updateCaptionsUI } from "./captions.js";
import { stopRecording } from "./recording.js";
import { appendMessage, appendSystemMessage } from "./chat.js";
import { 
    broadcast, 
    renderPollsUI, 
    renderQaUI, 
    handlePollLaunch, 
    handlePollVoteUpdate, 
    handlePollEnd, 
    handleQaNewQuestion, 
    handleQaUpvote, 
    handleQaAnswered 
} from "./polls.js";
import { getAuthToken } from "../auth.js";
import { BackgroundProcessor, supportsBackgroundProcessors } from "https://esm.sh/@livekit/track-processors@0.7.2";
import { KrispNoiseFilter } from "https://esm.sh/@livekit/krisp-noise-filter@0.1.3";
import * as LivekitClient from "https://esm.sh/livekit-client@2.20.1";

const { Room, RoomEvent, Track, DataPacket_Kind, VideoQuality, ExternalE2EEKeyProvider, ConnectionQuality } = LivekitClient;

const MAX_VISIBLE_TILES = 9;

// ==========================================
// MEETING CHRONOMETER / TIMER
// ==========================================
let _meetingTimerInterval = null;

export function startMeetingTimer(startedAtSec) {
    if (_meetingTimerInterval) {
        clearInterval(_meetingTimerInterval);
        _meetingTimerInterval = null;
    }
    const startTimestamp = (startedAtSec && startedAtSec > 0)
        ? startedAtSec
        : Math.floor(Date.now() / 1000);

    const update = () => {
        const el = document.getElementById('meetingTimerText');
        if (!el) return;
        const nowSec = Math.floor(Date.now() / 1000);
        const elapsed = Math.max(0, nowSec - startTimestamp);
        const hours = Math.floor(elapsed / 3600);
        const mins = Math.floor((elapsed % 3600) / 60);
        const secs = elapsed % 60;
        const pad = (n) => String(n).padStart(2, '0');
        if (hours > 0) {
            el.textContent = `${hours}:${pad(mins)}:${pad(secs)}`;
        } else {
            el.textContent = `${pad(mins)}:${pad(secs)}`;
        }
    };

    update();
    _meetingTimerInterval = setInterval(update, 1000);
}

export function stopMeetingTimer() {
    if (_meetingTimerInterval) {
        clearInterval(_meetingTimerInterval);
        _meetingTimerInterval = null;
    }
    const el = document.getElementById('meetingTimerText');
    if (el) el.textContent = '00:00';
}

// ==========================================
// CORE CALL LOGIC
// ==========================================
export async function startCall(roomId, options = {}) {
    const joinScreen = document.getElementById('joinScreen');
    const appLayout = document.getElementById('appLayout');
    const mediaControls = document.getElementById('mediaControls');
    const meetingInfo = document.getElementById('meetingInfo');
    const localVideo = document.getElementById('localVideo');
    const videoGrid = document.getElementById('videoGrid');
    const chatInput = document.getElementById('chatInput');
    const sendBtn = document.getElementById('sendBtn');
    const toggleMicBtn = document.getElementById('toggleMicBtn');
    const toggleVideoBtn = document.getElementById('toggleVideoBtn');

    try {
        if (joinScreen) joinScreen.style.display = 'none';
        if (appLayout) appLayout.style.display = 'flex';
        if (mediaControls) mediaControls.style.display = 'flex';

        if (meetingInfo) {
            meetingInfo.innerHTML = `
                <span class="material-symbols-outlined" style="font-size: 18px; color: var(--primary, #00E5FF);">info</span>
                <span class="meeting-code" style="font-family: monospace; font-size: 0.9rem; letter-spacing: 0.5px; margin: 0 4px;">${roomId}</span>
                <button class="copy-code-badge-btn" title="Copy Meeting Link" onclick="window.copyMeetingLink('${roomId}')">
                    <span class="material-symbols-outlined" style="font-size: 18px;">content_copy</span>
                </button>
                <span class="meeting-info-divider"></span>
                <div class="meeting-timer-pill" id="meetingTimer" title="Meeting duration">
                    <span class="material-symbols-outlined timer-icon">schedule</span>
                    <span id="meetingTimerText">00:00</span>
                </div>
            `;
        }

        const peerId = Math.random().toString(36).substring(2, 10);
        const fbToken = await getAuthToken();
        const headers = {};
        if (fbToken) { headers['Authorization'] = `Bearer ${fbToken}`; }

        let response = await fetch(`/token/${roomId}/${peerId}?name=${encodeURIComponent(state.userName)}`, { headers });
        if (!response.ok) {
            let errMsg = "Failed to connect to meeting room";
            try {
                const errData = await response.json();
                if (errData && errData.detail) {
                    errMsg = typeof errData.detail === 'string' ? errData.detail : (errData.detail.message || JSON.stringify(errData.detail));
                }
            } catch (_) {}
            throw new Error(errMsg);
        }
        const { token, is_admin, room_started_at } = await response.json();
        state.isAdmin = is_admin || false;
        startMeetingTimer(room_started_at);

        const toggleRecordBtn = document.getElementById('toggleRecordBtn');
        if (state.isAdmin && toggleRecordBtn) { toggleRecordBtn.style.display = 'flex'; }

        const toggleVmixBtn = document.getElementById('toggleVmixBtn');
        if (state.isAdmin && toggleVmixBtn) { toggleVmixBtn.style.display = 'flex'; }

        const toggleMultiStreamBtn = document.getElementById('toggleMultiStreamBtn');
        if (state.isAdmin && toggleMultiStreamBtn) { toggleMultiStreamBtn.style.display = 'flex'; }

        const muteAllBtn = document.getElementById('muteAllBtn');
        if (state.isAdmin && muteAllBtn) {
            muteAllBtn.style.display = 'flex';
            muteAllBtn.onclick = async () => {
                if (!state.currentRoom) return;
                const data = new TextEncoder().encode('__MUTE_ALL__');
                await state.currentRoom.localParticipant.publishData(data, { reliable: true });
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

        state.currentRoom = new Room({
            adaptiveStream: true,
            dynacast: true,
            audioCaptureDefaults: {
                autoGainControl: true,
                echoCancellation: true,
                noiseSuppression: true,
            },
            publishDefaults: {
                dtx: true,
                red: true,
                simulcast: true,
            },
            videoCaptureDefaults: { facingMode: state.currentFacingMode },
            e2ee: e2eeOptions
        });

        // Add signal bars to local video tile
        ensureLocalTileSignalBars();

        // Active Speakers Event
        state.currentRoom.on(RoomEvent.ActiveSpeakersChanged, (speakers) => {
            state.activeSpeakerSet.clear();
            speakers.forEach(p => state.activeSpeakerSet.add(p.identity));

            if (videoGrid) {
                videoGrid.querySelectorAll('.video-wrapper:not(.local)').forEach(wrapper => {
                    const id = wrapper.dataset.identity;
                    if (id) {
                        wrapper.classList.toggle('speaking', state.activeSpeakerSet.has(id));
                    }
                });
            }
            _reorderGridByActiveSpeakers();
        });

        // Track Published
        state.currentRoom.on(RoomEvent.TrackPublished, (publication, participant) => {
            const isScreenShare = publication.source === Track.Source.ScreenShare || publication.source === 'screen_share';
            if (state.isDataSaverMode && publication.kind === 'video' && !isScreenShare) {
                publication.setSubscribed(false);
            }
        });

        // Track Subscribed
        state.currentRoom.on(RoomEvent.TrackSubscribed, (track, publication, participant) => {
            const isScreenShare = publication.source === Track.Source.ScreenShare || publication.source === 'screen_share';
            if (state.isDataSaverMode && track.kind === 'video' && !isScreenShare) {
                publication.setSubscribed(false);
                return;
            }
            if (track.kind === 'video') {
                attachVideoTrack(track, participant, publication.source);
            } else if (track.kind === 'audio') {
                const audioElement = track.attach();
                document.body.appendChild(audioElement);

                if (state.recordingAudioContext && state.recordingDestinationNode && track.mediaStreamTrack) {
                    if (!state.audioSourceNodes.has(track.sid)) {
                        const source = state.recordingAudioContext.createMediaStreamSource(new MediaStream([track.mediaStreamTrack]));
                        source.connect(state.recordingDestinationNode);
                        state.audioSourceNodes.set(track.sid, source);
                    }
                }
            }
            _updateParticipantOrder();
            _applySubscriptionQualities();
            renderParticipants();
        });

        // Track Unsubscribed
        state.currentRoom.on(RoomEvent.TrackUnsubscribed, (track, publication, participant) => {
            track.detach().forEach(el => el.remove());
            if (track.kind === 'video') {
                const wrapper = document.getElementById(`wrapper-${participant.identity}-${publication.source}`);
                if (wrapper) {
                    unobserveTile(wrapper);
                    wrapper.remove();
                }
                updateVideoGridClass();
            }
            _updateParticipantOrder();
            _applySubscriptionQualities();
            renderParticipants();
        });

        // Track Muted / Unmuted
        state.currentRoom.on(RoomEvent.TrackMuted, (pub, participant) => {
            if (pub.kind === 'video') {
                const wrapper = document.getElementById(`wrapper-${participant.identity}-${pub.source}`);
                if (wrapper) wrapper.classList.add('video-muted');
            }
        });

        state.currentRoom.on(RoomEvent.TrackUnmuted, (pub, participant) => {
            if (pub.kind === 'video') {
                const wrapper = document.getElementById(`wrapper-${participant.identity}-${pub.source}`);
                if (wrapper) wrapper.classList.remove('video-muted');
            }
        });

        // Participant Connected / Disconnected
        state.currentRoom.on(RoomEvent.ParticipantConnected, (participant) => {
            appendSystemMessage(`${participant.name || participant.identity} joined.`);
            _updateParticipantOrder();
            _applySubscriptionQualities();
            renderParticipants();
            updateConnectionQuality(participant, ConnectionQuality.Excellent);
        });

        state.currentRoom.on(RoomEvent.ParticipantDisconnected, (participant) => {
            appendSystemMessage(`${participant.name || participant.identity} left.`);
            _teardownSpeakingIndicator(participant.identity);
            state.raisedHands.delete(participant.identity);
            
            const wrappers = document.querySelectorAll(`[id^="wrapper-${participant.identity}-"]`);
            wrappers.forEach(w => {
                unobserveTile(w);
                w.remove();
            });
            updateVideoGridClass();
            _updateParticipantOrder();
            _applySubscriptionQualities();
            renderParticipants();
        });

        // Connection Quality Changed Event
        state.currentRoom.on(RoomEvent.ConnectionQualityChanged, (quality, participant) => {
            updateConnectionQuality(participant, quality);
            const isLocal = state.currentRoom && state.currentRoom.localParticipant && state.currentRoom.localParticipant.identity === participant.identity;
            if (isLocal && quality === ConnectionQuality.Poor && !state.isDataSaverMode) {
                const now = Date.now();
                if (!state._lastPoorConnWarning || now - state._lastPoorConnWarning > 30000) {
                    state._lastPoorConnWarning = now;
                    showToast("Your connection is weak. Consider enabling Data Saver mode.", 5000);
                }
            }
        });

        // Data Messages Received
        state.currentRoom.on(RoomEvent.DataReceived, (payload, participant, kind) => {
            const str = new TextDecoder().decode(payload);
            try {
                const data = JSON.parse(str);
                if (data.type === 'chat') {
                    appendMessage(data.sender, data.text, false);
                    const chatSidebar = document.querySelector('.chat-sidebar:not(.people-sidebar)');
                    if (chatSidebar && !chatSidebar.classList.contains('active')) {
                        const badge = document.getElementById('chatBadge');
                        if (badge) badge.style.display = 'block';
                    }
                } else if (data.type === 'reaction') {
                    showReaction(data.senderId, data.emoji);
                } else if (data.type === 'raise_hand') {
                    updateHandRaiseUI(data.senderId, data.state);
                } else if (data.type === 'whiteboard_toggle') {
                    handleRemoteWhiteboardToggle(data.state);
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
                } else if (data.type === 'caption') {
                    handleIncomingCaption(data);
                }
            } catch (e) {
                if (str === '__MUTE_ALL__' && !state.isAdmin) {
                    if (state.currentRoom && state.currentRoom.localParticipant) {
                        state.currentRoom.localParticipant.setMicrophoneEnabled(false);
                        state.isMicEnabled = false;
                        if (toggleMicBtn) {
                            toggleMicBtn.classList.remove('active');
                            const icon = toggleMicBtn.querySelector('.material-symbols-outlined');
                            if (icon) icon.textContent = 'mic_off';
                            const txt = toggleMicBtn.querySelector('.btn-text');
                            if (txt) txt.textContent = 'Unmute';
                        }
                        showToast("The host muted everyone.");
                    }
                } else if (str.startsWith('__MUTE_PARTICIPANT__:')) {
                    const targetId = str.split(':')[1];
                    if (state.currentRoom && state.currentRoom.localParticipant.identity === targetId) {
                        state.currentRoom.localParticipant.setMicrophoneEnabled(false);
                        state.isMicEnabled = false;
                        if (toggleMicBtn) {
                            toggleMicBtn.classList.remove('active');
                            const icon = toggleMicBtn.querySelector('.material-symbols-outlined');
                            if (icon) icon.textContent = 'mic_off';
                            const txt = toggleMicBtn.querySelector('.btn-text');
                            if (txt) txt.textContent = 'Unmute';
                        }
                        showToast("You were muted by the host.");
                    }
                }
            }
        });

        // Determine WebRTC server URL
        let wsUrl = state.livekitUrlFallback || "wss://lavie-live-bmlbvgd2.livekit.cloud";
        try {
            const healthCheck = await fetch('/livekit-url');
            if (healthCheck.ok) {
                const cfg = await healthCheck.json();
                if (cfg && (cfg.url || cfg.livekit_url)) {
                    wsUrl = cfg.url || cfg.livekit_url;
                }
            }
        } catch (_) {}

        await state.currentRoom.connect(wsUrl, token);

        // Apply green room device preferences if provided
        const enableMicAtStart = options.isMicEnabled !== undefined ? options.isMicEnabled : state.isMicEnabled;
        const enableVideoAtStart = options.isVideoEnabled !== undefined ? options.isVideoEnabled : state.isVideoEnabled;
        const chosenCamId = options.cameraDeviceId || state.activeCameraDeviceId;
        const chosenMicId = options.audioDeviceId || state.activeAudioInputDeviceId;

        let camDenied = false;
        let micDenied = false;

        // Publish Camera
        try {
            if (enableVideoAtStart) {
                const camOptions = chosenCamId ? { deviceId: chosenCamId } : true;
                await state.currentRoom.localParticipant.setCameraEnabled(true, camOptions);
                state.isVideoEnabled = true;
                if (toggleVideoBtn) {
                    toggleVideoBtn.classList.add('active');
                    const icon = toggleVideoBtn.querySelector('.material-symbols-outlined');
                    if (icon) icon.textContent = 'videocam';
                    const txt = toggleVideoBtn.querySelector('.btn-text');
                    if (txt) txt.textContent = 'Hide';
                }
            } else {
                await state.currentRoom.localParticipant.setCameraEnabled(false);
                state.isVideoEnabled = false;
                if (toggleVideoBtn) {
                    toggleVideoBtn.classList.remove('active');
                    const icon = toggleVideoBtn.querySelector('.material-symbols-outlined');
                    if (icon) icon.textContent = 'videocam_off';
                    const txt = toggleVideoBtn.querySelector('.btn-text');
                    if (txt) txt.textContent = 'Show';
                }
            }

            const videoTrack = state.currentRoom.localParticipant.getTrackPublication(Track.Source.Camera)?.videoTrack;
            if (videoTrack && localVideo) {
                videoTrack.attach(localVideo);
            }
        } catch (camErr) {
            console.warn("Camera permission denied or unavailable:", camErr);
            camDenied = true;
            state.isVideoEnabled = false;
            if (toggleVideoBtn) {
                toggleVideoBtn.classList.remove('active');
                const icon = toggleVideoBtn.querySelector('.material-symbols-outlined');
                if (icon) icon.textContent = 'videocam_off';
                const txt = toggleVideoBtn.querySelector('.btn-text');
                if (txt) txt.textContent = 'Show';
            }
        }

        // Publish Microphone
        try {
            if (enableMicAtStart) {
                const micOptions = chosenMicId ? { deviceId: chosenMicId } : true;
                await state.currentRoom.localParticipant.setMicrophoneEnabled(true, micOptions, { dtx: true });
                state.isMicEnabled = true;
                if (toggleMicBtn) {
                    toggleMicBtn.classList.add('active');
                    const icon = toggleMicBtn.querySelector('.material-symbols-outlined');
                    if (icon) icon.textContent = 'mic';
                    const txt = toggleMicBtn.querySelector('.btn-text');
                    if (txt) txt.textContent = 'Mute';
                }
            } else {
                await state.currentRoom.localParticipant.setMicrophoneEnabled(false);
                state.isMicEnabled = false;
                if (toggleMicBtn) {
                    toggleMicBtn.classList.remove('active');
                    const icon = toggleMicBtn.querySelector('.material-symbols-outlined');
                    if (icon) icon.textContent = 'mic_off';
                    const txt = toggleMicBtn.querySelector('.btn-text');
                    if (txt) txt.textContent = 'Unmute';
                }
            }
        } catch (micErr) {
            console.warn("Microphone permission denied or unavailable:", micErr);
            micDenied = true;
            state.isMicEnabled = false;
            if (toggleMicBtn) {
                toggleMicBtn.classList.remove('active');
                const icon = toggleMicBtn.querySelector('.material-symbols-outlined');
                if (icon) icon.textContent = 'mic_off';
                const txt = toggleMicBtn.querySelector('.btn-text');
                if (txt) txt.textContent = 'Unmute';
            }
        }

        if (camDenied && micDenied) {
            showToast("Camera & Mic blocked. You joined in listen-only mode.", false);
        } else if (camDenied) {
            showToast("Camera blocked. Joined with microphone only.", false);
        } else if (micDenied) {
            showToast("Microphone blocked. Joined with camera only.", false);
        }

        // Network Information API detection for slow networks
        if (typeof navigator !== 'undefined' && 'connection' in navigator) {
            const conn = navigator.connection;
            const checkSlowNetwork = () => {
                if (state.isDataSaverMode) return;
                const isSlow = conn.saveData || conn.effectiveType === '2g' || conn.effectiveType === 'slow-2g' || (conn.downlink && conn.downlink < 0.5);
                if (isSlow) {
                    showToast("Slow network detected. Turn on Data Saver to prioritize audio.", 5000);
                }
            };
            checkSlowNetwork();
            if (conn.addEventListener) {
                conn.addEventListener('change', checkSlowNetwork, { once: true });
            }
        }

        try { await updateCameraDevicesList(); } catch (e) {}
        try { await updateAudioDevicesList(); } catch (e) {}
        try { updateAudioOutputButtonState(); } catch (e) {}

        try {
            if (supportsBackgroundProcessors()) {
                state.backgroundProcessor = BackgroundProcessor({ mode: 'disabled' });
                const videoTrack = state.currentRoom.localParticipant.getTrackPublication(Track.Source.Camera)?.videoTrack;
                if (videoTrack) { await videoTrack.setProcessor(state.backgroundProcessor); }
            }
        } catch (e) { console.warn("Background processor initialization failed", e); }

        try { state.krispFilter = KrispNoiseFilter(); }
        catch (e) { console.warn("Krisp noise filter initialization failed", e); }

        _updateParticipantOrder();
        _applySubscriptionQualities();
        updateVideoGridClass();
        renderParticipants();

        // Restore Data Saver Mode if saved in preferences
        if (localStorage.getItem('lavie_data_saver') === 'true') {
            toggleDataSaverMode(true);
        } else {
            updateDataSaverBanner();
        }

        if (chatInput) chatInput.disabled = false;
        if (sendBtn) sendBtn.disabled = false;
        appendSystemMessage("You connected to the room.");
        window.history.pushState({}, '', `?room=${roomId}`);

    } catch (err) {
        console.error("Connection error:", err);
        const friendlyMsg = formatFriendlyErrorMessage(err);
        if (friendlyMsg) {
            showToast(friendlyMsg, true);
        }
        leaveCall();
    }
}

// ==========================================
// CONNECTION QUALITY & SIGNAL BARS
// ==========================================
function normalizeQuality(quality) {
    if (!quality) return 'excellent';
    const q = String(quality).toLowerCase();
    if (q.includes('poor') || q.includes('lost')) return 'poor';
    if (q.includes('good')) return 'good';
    if (q.includes('excellent')) return 'excellent';
    return 'good';
}

export function updateConnectionQuality(participant, quality) {
    if (!participant) return;
    const qClass = normalizeQuality(quality);
    const identity = participant.identity;

    const isLocal = state.currentRoom && state.currentRoom.localParticipant && state.currentRoom.localParticipant.identity === identity;

    if (isLocal) {
        const localWrapper = document.getElementById('wrapper-local-camera');
        if (localWrapper) {
            const bars = localWrapper.querySelector('.signal-bars');
            if (bars) {
                bars.setAttribute('data-quality', qClass);
                bars.setAttribute('title', `Connection: ${qClass.charAt(0).toUpperCase() + qClass.slice(1)}`);
            }
        }
    }

    const wrappers = document.querySelectorAll(`[id^="wrapper-${identity}-"]`);
    wrappers.forEach(wrapper => {
        const bars = wrapper.querySelector('.signal-bars');
        if (bars) {
            bars.setAttribute('data-quality', qClass);
            bars.setAttribute('title', `Connection: ${qClass.charAt(0).toUpperCase() + qClass.slice(1)}`);
        }
    });
}

function ensureLocalTileSignalBars() {
    const localWrapper = document.getElementById('wrapper-local-camera');
    if (!localWrapper) return;
    if (!localWrapper.querySelector('.signal-bars')) {
        const signalBars = document.createElement('div');
        signalBars.className = 'signal-bars';
        signalBars.setAttribute('data-quality', 'excellent');
        signalBars.setAttribute('title', 'Connection: Excellent');
        signalBars.innerHTML = '<span></span><span></span><span></span>';
        localWrapper.appendChild(signalBars);
    }
}

// ==========================================
// ATTACH VIDEO TRACK & TILES
// ==========================================
export function attachVideoTrack(track, participant, source) {
    const videoGrid = document.getElementById('videoGrid');
    if (!videoGrid) return;

    let wrapper = document.getElementById(`wrapper-${participant.identity}-${source}`);
    if (!wrapper) {
        wrapper = document.createElement('div');
        wrapper.className = 'video-wrapper';
        wrapper.id = `wrapper-${participant.identity}-${source}`;
        wrapper.dataset.identity = participant.identity;

        const label = document.createElement('span');
        label.className = 'label';
        const srcText = source === Track.Source.ScreenShare ? "'s Screen" : "";
        label.textContent = (participant.name || participant.identity) + srcText;

        // Signal bars indicator
        const signalBars = document.createElement('div');
        signalBars.className = 'signal-bars';
        signalBars.setAttribute('data-quality', normalizeQuality(participant.connectionQuality));
        signalBars.setAttribute('title', `Connection: ${normalizeQuality(participant.connectionQuality)}`);
        signalBars.innerHTML = '<span></span><span></span><span></span>';

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
        wrapper.appendChild(signalBars);
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

        if (source === Track.Source.ScreenShare || source === 'screen_share') {
            wrapper.classList.add('screen-share');
        }

        if (state.isAdmin && participant && state.currentRoom && participant.identity !== state.currentRoom.localParticipant.identity && source !== Track.Source.ScreenShare) {
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

        wrapper.dataset.source = source;
        videoGrid.appendChild(wrapper);
        observeTile(wrapper);
    }

    const videoElement = track.attach();
    if (source === Track.Source.ScreenShare) {
        videoElement.style.objectFit = 'contain';
        videoElement.style.backgroundColor = '#000';
    }
    wrapper.insertBefore(videoElement, wrapper.firstChild);
    updateVideoGridClass();
}

// ==========================================
// LEAVE CALL
// ==========================================
export function leaveCall() {
    if (state.currentRoom) {
        try { state.currentRoom.disconnect(); } catch(e) {}
        state.currentRoom = null;
    }

    const appLayout = document.getElementById('appLayout');
    const joinScreen = document.getElementById('joinScreen');
    const videoGrid = document.getElementById('videoGrid');
    const chatMessages = document.getElementById('chatMessages');
    const toggleMicBtn = document.getElementById('toggleMicBtn');
    const toggleVideoBtn = document.getElementById('toggleVideoBtn');
    const toggleScreenBtn = document.getElementById('toggleScreenBtn');
    const toggleNoiseBtn = document.getElementById('toggleNoiseBtn');
    const toggleWhiteboardBtn = document.getElementById('toggleWhiteboardBtn');
    const mainColumn = document.getElementById('mainColumn');
    const whiteboardContainer = document.getElementById('whiteboardContainer');
    const pollQaSidebar = document.getElementById('pollQaSidebar');
    const togglePollsBtn = document.getElementById('togglePollsBtn') || document.getElementById('navPollsBtn');
    const qaBadge = document.getElementById('qaBadge');
    const chatInput = document.getElementById('chatInput');
    const sendBtn = document.getElementById('sendBtn');
    const toggleRecordBtn = document.getElementById('toggleRecordBtn');

    stopMeetingTimer();

    if (appLayout) appLayout.style.display = 'none';
    if (joinScreen) joinScreen.style.display = 'block';
    window.history.pushState({}, '', window.location.pathname);

    state.speakingAnalysers.forEach((_, identity) => _teardownSpeakingIndicator(identity));
    state.speakingAnalysers.clear();
    state.activeSpeakerSet.clear();
    state.participantOrder = [];
    state.participantDomMap.clear();

    if (state.sharedAudioContext) {
        try { state.sharedAudioContext.close(); } catch(e) {}
        state.sharedAudioContext = null;
    }

    if (videoGrid) {
        const wrappers = videoGrid.querySelectorAll('.video-wrapper:not(.local)');
        wrappers.forEach(w => w.remove());
        const badge = document.getElementById('tile-overflow-badge');
        if (badge) badge.remove();
    }

    updateVideoGridClass();

    if (chatMessages) {
        chatMessages.innerHTML = '<div class="chat-system">Messages can only be seen by people in the call and are deleted when the call ends.</div>';
    }

    state.isMicEnabled = true;
    state.isVideoEnabled = true;
    state.isScreenSharing = false;

    if (toggleMicBtn) {
        toggleMicBtn.classList.add('active');
        const icon = toggleMicBtn.querySelector('.material-symbols-outlined');
        if (icon) icon.textContent = 'mic';
        const txt = toggleMicBtn.querySelector('.btn-text');
        if (txt) txt.textContent = 'Mute';
    }
    if (toggleVideoBtn) {
        toggleVideoBtn.classList.add('active');
        const icon = toggleVideoBtn.querySelector('.material-symbols-outlined');
        if (icon) icon.textContent = 'videocam';
        const txt = toggleVideoBtn.querySelector('.btn-text');
        if (txt) txt.textContent = 'Hide';
    }
    if (toggleScreenBtn) {
        toggleScreenBtn.classList.remove('active');
        const icon = toggleScreenBtn.querySelector('.material-symbols-outlined');
        if (icon) icon.textContent = 'present_to_all';
        const txt = toggleScreenBtn.querySelector('.btn-text');
        if (txt) txt.textContent = 'Share';
    }

    if (state.backgroundProcessor) {
        try { state.backgroundProcessor.switchTo({ mode: 'disabled' }); } catch(e) {}
    }
    if (toggleNoiseBtn) {
        state.isNoiseCancellationEnabled = false;
        toggleNoiseBtn.classList.remove('active');
    }

    if (toggleWhiteboardBtn) {
        state.isWhiteboardActive = false;
        toggleWhiteboardBtn.classList.remove('active');
    }
    if (mainColumn) mainColumn.classList.remove('with-whiteboard');
    if (whiteboardContainer) {
        whiteboardContainer.classList.remove('active');
        whiteboardContainer.innerHTML = '';
    }

    state.activePoll = null;
    state.localVotedOption = null;
    state.qaQuestions = [];
    state.localQaUpvoted = new Set();
    state.newQaCount = 0;
    if (pollQaSidebar) { pollQaSidebar.classList.remove('open'); state.isPollQaOpen = false; }
    if (togglePollsBtn) togglePollsBtn.classList.remove('active');
    if (qaBadge) qaBadge.style.display = 'none';
    renderPollsUI();
    renderQaUI();

    if (toggleRecordBtn) toggleRecordBtn.style.display = 'none';
    stopRecording();

    // Reset Live Captions & Data Saver banner on leave
    stopSpeechRecognition();
    state.isCaptionsEnabled = false;
    updateCaptionsUI(false);
    const captionsContainer = document.getElementById('liveCaptionsContainer');
    if (captionsContainer) {
        captionsContainer.style.display = 'none';
        captionsContainer.innerHTML = '';
    }
    const dataSaverBanner = document.getElementById('dataSaverActiveBanner');
    if (dataSaverBanner) dataSaverBanner.remove();

    cleanupTileObserver();
    state._lastPoorConnWarning = 0;

    if (chatInput) chatInput.disabled = true;
    if (sendBtn) sendBtn.disabled = true;
}
window.leaveCall = leaveCall;

// ==========================================
// TILE VIEWPORT OBSERVER (IntersectionObserver)
// ==========================================
let _tileObserver = null;

function _getTileObserver() {
    if (_tileObserver) return _tileObserver;
    if (typeof IntersectionObserver === 'undefined') return null;

    _tileObserver = new IntersectionObserver((entries) => {
        if (!state.currentRoom || state.isDataSaverMode) return;
        entries.forEach(entry => {
            const target = entry.target;
            const identity = target.dataset.identity;
            const source = target.dataset.source;
            if (!identity || source === Track.Source.ScreenShare || source === 'screen_share') return;

            const participant = state.currentRoom.getParticipantByIdentity(identity);
            if (!participant) return;

            participant.videoTrackPublications.forEach(pub => {
                if (pub.kind === 'video' && pub.source !== Track.Source.ScreenShare) {
                    if (entry.isIntersecting) {
                        pub.setEnabled(true);
                    } else {
                        // Off-screen tile: suspend stream packet reception to conserve data
                        pub.setEnabled(false);
                    }
                }
            });
        });
    }, {
        root: document.getElementById('videoGrid'),
        threshold: 0.05
    });

    return _tileObserver;
}

export function observeTile(wrapper) {
    const obs = _getTileObserver();
    if (obs && wrapper) {
        obs.observe(wrapper);
    }
}

export function unobserveTile(wrapper) {
    if (_tileObserver && wrapper) {
        _tileObserver.unobserve(wrapper);
    }
}

export function cleanupTileObserver() {
    if (_tileObserver) {
        _tileObserver.disconnect();
        _tileObserver = null;
    }
}

// ==========================================
// GRID REORDERING & ACTIVE SPEAKERS
// ==========================================
function _updateParticipantOrder() {
    if (!state.currentRoom) return;
    const allRemote = [];
    state.currentRoom.remoteParticipants.forEach(p => allRemote.push(p.identity));

    allRemote.sort((a, b) => {
        const aActive = state.activeSpeakerSet.has(a);
        const bActive = state.activeSpeakerSet.has(b);
        if (aActive && !bActive) return -1;
        if (!aActive && bActive) return 1;
        return 0;
    });
    state.participantOrder = allRemote;
}

function _reorderGridByActiveSpeakers() {
    const videoGrid = document.getElementById('videoGrid');
    if (!state.currentRoom || !videoGrid) return;
    _updateParticipantOrder();

    state.participantOrder.forEach((identity) => {
        const cameraTile = document.getElementById(`wrapper-${identity}-${Track.Source.Camera}`);
        const screenTile = document.getElementById(`wrapper-${identity}-${Track.Source.ScreenShare}`);
        if (cameraTile) videoGrid.appendChild(cameraTile);
        if (screenTile) videoGrid.appendChild(screenTile);
    });
}

function _applySubscriptionQualities() {
    if (!state.currentRoom || state.isDataSaverMode) return;
    const topIdentities = new Set(state.participantOrder.slice(0, MAX_VISIBLE_TILES));

    state.currentRoom.remoteParticipants.forEach(participant => {
        const isVisible = topIdentities.has(participant.identity);
        participant.videoTrackPublications.forEach(pub => {
            const isScreenShare = pub.source === Track.Source.ScreenShare || pub.source === 'screen_share';
            if (isScreenShare) {
                pub.setEnabled(true);
                pub.setVideoQuality(VideoQuality.HIGH);
                return;
            }
            if (pub.track) {
                if (isVisible) {
                    pub.setEnabled(true);
                    const isSpeaking = state.activeSpeakerSet.has(participant.identity);
                    const isPinned = state.pinnedWrapperId && state.pinnedWrapperId.includes(participant.identity);
                    pub.setVideoQuality((isSpeaking || isPinned) ? VideoQuality.HIGH : VideoQuality.HIGH);
                } else {
                    // Participant is beyond max visible tiles: suspend video stream to save ~200kbps per tile
                    pub.setEnabled(false);
                    pub.setVideoQuality(VideoQuality.LOW);
                }
            }
        });
    });
}

export function updateVideoGridClass() {
    const videoGrid = document.getElementById('videoGrid');
    if (!videoGrid) return;
    const count = videoGrid.querySelectorAll('.video-wrapper').length;
    const classesToRemove = Array.from(videoGrid.classList).filter(c => c.startsWith('grid-count-'));
    classesToRemove.forEach(c => videoGrid.classList.remove(c));
    videoGrid.classList.add(`grid-count-${count}`);
}

export function togglePin(wrapperId) {
    const grid = document.getElementById('videoGrid');
    if (!grid) return;
    if (state.pinnedWrapperId === wrapperId) {
        const current = document.getElementById(state.pinnedWrapperId);
        if (current) current.classList.remove('pinned');
        grid.classList.remove('has-pinned');
        state.pinnedWrapperId = null;
        return;
    }
    if (state.pinnedWrapperId) {
        const prev = document.getElementById(state.pinnedWrapperId);
        if (prev) prev.classList.remove('pinned');
    }
    const newPinned = document.getElementById(wrapperId);
    if (newPinned) {
        newPinned.classList.add('pinned');
        grid.classList.add('has-pinned');
        state.pinnedWrapperId = wrapperId;
    }
}

export function toggleWrapperFullscreen(wrapper) {
    if (!wrapper) return;
    const isFs = document.fullscreenElement === wrapper ||
                 document.webkitFullscreenElement === wrapper ||
                 document.mozFullScreenElement === wrapper ||
                 document.msFullscreenElement === wrapper;

    if (isFs) {
        if (document.exitFullscreen) document.exitFullscreen().catch(console.error);
        else if (document.webkitExitFullscreen) document.webkitExitFullscreen();
    } else {
        if (wrapper.requestFullscreen) {
            wrapper.requestFullscreen().catch(err => {
                const video = wrapper.querySelector('video');
                if (video && video.webkitEnterFullscreen) video.webkitEnterFullscreen();
            });
        } else if (wrapper.webkitRequestFullscreen) {
            wrapper.webkitRequestFullscreen();
        }
    }
}

function _teardownSpeakingIndicator(participantIdentity) {
    const resources = state.speakingAnalysers.get(participantIdentity);
    if (!resources) return;
    if (resources.rafId) cancelAnimationFrame(resources.rafId);
    try { resources.source.disconnect(); } catch(e) {}
    try { resources.analyser.disconnect(); } catch(e) {}
    state.speakingAnalysers.delete(participantIdentity);
}

// ==========================================
// PARTICIPANT LIST RENDERING
// ==========================================
export function renderParticipants() {
    const peopleList = document.getElementById('peopleList');
    if (!state.currentRoom || !peopleList) return;

    const currentIds = new Set();
    const local = state.currentRoom.localParticipant;
    if (local) {
        currentIds.add('local-' + local.identity);
        let el = state.participantDomMap.get('local-' + local.identity);
        if (!el) {
            el = createParticipantElement(local, true);
            state.participantDomMap.set('local-' + local.identity, el);
            peopleList.prepend(el);
        } else {
            _updateParticipantElement(el, local, true);
        }
    }

    state.currentRoom.remoteParticipants.forEach((p) => {
        const key = 'remote-' + p.identity;
        currentIds.add(key);
        let el = state.participantDomMap.get(key);
        if (!el) {
            el = createParticipantElement(p, false);
            state.participantDomMap.set(key, el);
            peopleList.appendChild(el);
        } else {
            _updateParticipantElement(el, p, false);
        }
    });

    state.participantDomMap.forEach((el, key) => {
        if (!currentIds.has(key)) {
            el.remove();
            state.participantDomMap.delete(key);
        }
    });
}

function _updateParticipantElement(el, participant, isLocal) {
    const name = participant.name || participant.identity;
    const hasHand = state.raisedHands.has(participant.identity);
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
    nameDiv.textContent = `${name}${isLocal ? ' (You)' : ''}${state.raisedHands.has(participant.identity) ? ' ✋' : ''}`;

    infoDiv.appendChild(avatarDiv);
    infoDiv.appendChild(nameDiv);
    div.appendChild(infoDiv);

    if (state.isAdmin && !isLocal) {
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

export async function muteParticipant(identity) {
    if (!state.isAdmin || !state.currentRoom) return;
    try {
        const data = new TextEncoder().encode(`__MUTE_PARTICIPANT__:${identity}`);
        await state.currentRoom.localParticipant.publishData(data, { reliable: true });
        showToast("Participant muted");
    } catch(err) { showToast("Error muting participant", true); }
}
window.muteParticipant = muteParticipant;

export async function kickParticipant(identity) {
    if (!state.isAdmin || !state.currentRoom) return;
    try {
        const fbToken = await getAuthToken();
        const res = await fetch('/api/kick', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${fbToken}` },
            body: JSON.stringify({ room_id: state.currentRoom.name, identity })
        });
        if (!res.ok) throw new Error("Failed to remove");
        showToast("Participant removed");
    } catch(err) { showToast("Error removing participant", true); }
}
window.kickParticipant = kickParticipant;

export function showReaction(identity, emoji) {
    if (!identity) return;
    const wrappers = document.querySelectorAll(`[id^="wrapper-${identity}-"], #wrapper-local-camera`);
    if (wrappers.length === 0) return;
    const wrapper = wrappers[0];
    const emojiEl = document.createElement('div');
    emojiEl.className = 'floating-emoji';
    emojiEl.textContent = emoji;
    wrapper.appendChild(emojiEl);
    setTimeout(() => { if (emojiEl.parentNode) emojiEl.remove(); }, 2500);
}

export function updateHandRaiseUI(identity, isRaised) {
    if (!identity) return;
    if (isRaised) { state.raisedHands.add(identity); } else { state.raisedHands.delete(identity); }
    const wrappers = document.querySelectorAll(`[id^="wrapper-${identity}-"], #wrapper-local-camera`);
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

function handleRemoteWhiteboardToggle(isActive) {
    const mainColumn = document.getElementById('mainColumn');
    const whiteboardContainer = document.getElementById('whiteboardContainer');
    const toggleWhiteboardBtn = document.getElementById('toggleWhiteboardBtn') || document.getElementById('navWhiteboardBtn');

    state.isWhiteboardActive = isActive;
    if (toggleWhiteboardBtn) toggleWhiteboardBtn.classList.toggle('active', isActive);
    if (isActive) {
        if (mainColumn) mainColumn.classList.add('with-whiteboard');
        if (whiteboardContainer) {
            whiteboardContainer.classList.add('active');
            if (!whiteboardContainer.querySelector('iframe') && state.currentRoom) {
                const iframe = document.createElement('iframe');
                iframe.src = `https://wbo.ophir.dev/boards/lavie-${state.currentRoom.name}`;
                whiteboardContainer.appendChild(iframe);
            }
        }
    } else {
        if (mainColumn) mainColumn.classList.remove('with-whiteboard');
        if (whiteboardContainer) whiteboardContainer.classList.remove('active');
    }
}
