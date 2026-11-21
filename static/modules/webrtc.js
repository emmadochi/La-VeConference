// ==========================================
// WEBRTC CALL ENGINE & PARTICIPANT MANAGEMENT
// ==========================================
import { state } from "./state.js";
import { showToast, copyMeetingLink, escapeHtml, formatFriendlyErrorMessage } from "./utils.js";
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

export function syncLocalMediaUI() {
    const lp = state.currentRoom?.localParticipant;
    if (!lp) return;

    const micPub = lp.getTrackPublication(Track.Source.Microphone);
    const micLive = Boolean(lp.isMicrophoneEnabled && micPub && !micPub.isMuted);
    state.isMicEnabled = micLive;

    const camPub = lp.getTrackPublication(Track.Source.Camera);
    const camLive = Boolean(lp.isCameraEnabled && camPub && !camPub.isMuted);
    state.isVideoEnabled = camLive;

    const localWrapper = document.getElementById('wrapper-local-camera');
    const localVideo = document.getElementById('localVideo');
    const toggleMicBtn = document.getElementById('toggleMicBtn');
    const toggleVideoBtn = document.getElementById('toggleVideoBtn');

    if (localWrapper) {
        localWrapper.classList.toggle('audio-muted', !micLive);
        localWrapper.classList.toggle('video-muted', !camLive);
        localWrapper.classList.toggle('video-off', !camLive);
    }
    const micIcon = document.getElementById('localMicStatusIcon');
    const micText = document.getElementById('localMicStatusText');
    const micPill = document.getElementById('localMicStatusPill');
    if (micIcon) micIcon.textContent = micLive ? 'mic' : 'mic_off';
    if (micText) micText.textContent = micLive ? 'Mic active' : 'Muted';
    if (micPill) micPill.classList.toggle('pill-muted', !micLive);

    if (toggleMicBtn) {
        toggleMicBtn.classList.toggle('active', micLive);
        toggleMicBtn.classList.toggle('muted-off', !micLive);
        const icon = toggleMicBtn.querySelector('.material-symbols-outlined');
        const txt = toggleMicBtn.querySelector('.btn-subtext') || toggleMicBtn.querySelector('.btn-text');
        if (icon) icon.textContent = micLive ? 'mic' : 'mic_off';
        if (txt) txt.textContent = micLive ? 'Mute' : 'Muted';
    }

    if (toggleVideoBtn) {
        toggleVideoBtn.classList.toggle('active', camLive);
        toggleVideoBtn.classList.toggle('muted-off', !camLive);
        const icon = toggleVideoBtn.querySelector('.material-symbols-outlined');
        const txt = toggleVideoBtn.querySelector('.btn-subtext') || toggleVideoBtn.querySelector('.btn-text');
        if (icon) icon.textContent = camLive ? 'videocam' : 'videocam_off';
        if (txt) txt.textContent = camLive ? 'Camera' : 'Camera Off';
    }

    if (camLive && camPub?.videoTrack && localVideo) {
        camPub.videoTrack.attach(localVideo);
    }
}

// ==========================================
// MEETING CHRONOMETER / TIMER
// ==========================================
let _meetingTimerInterval = null;

export function startMeetingTimer(startedAtSec, scheduledTimeSec = null) {
    if (_meetingTimerInterval) {
        clearInterval(_meetingTimerInterval);
        _meetingTimerInterval = null;
    }
    let activeStartTimestamp = (startedAtSec && startedAtSec > 0)
        ? startedAtSec
        : null;

    const update = () => {
        const el = document.getElementById('meetingTimerText');
        if (!el) return;
        const nowSec = Math.floor(Date.now() / 1000);
        const pad = (n) => String(n).padStart(2, '0');

        // If meeting is scheduled in the future, wait in countdown mode until scheduled time arrives
        if (scheduledTimeSec && nowSec < scheduledTimeSec) {
            const remaining = Math.max(0, scheduledTimeSec - nowSec);
            const rHours = Math.floor(remaining / 3600);
            const rMins = Math.floor((remaining % 3600) / 60);
            const rSecs = remaining % 60;
            el.textContent = rHours > 0
                ? `Starts in ${rHours}:${pad(rMins)}:${pad(rSecs)}`
                : `Starts in ${pad(rMins)}:${pad(rSecs)}`;
            return;
        }

        if (!activeStartTimestamp) {
            activeStartTimestamp = scheduledTimeSec && nowSec >= scheduledTimeSec
                ? scheduledTimeSec
                : nowSec;
        }

        const elapsed = Math.max(0, nowSec - activeStartTimestamp);
        const hours = Math.floor(elapsed / 3600);
        const mins = Math.floor((elapsed % 3600) / 60);
        const secs = elapsed % 60;
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

    const enableMicAtStart = options.isMicEnabled !== undefined ? options.isMicEnabled : state.isMicEnabled;
    const enableVideoAtStart = options.isVideoEnabled !== undefined ? options.isVideoEnabled : state.isVideoEnabled;

    try {
        document.body.classList.add('in-call');
        if (joinScreen) joinScreen.style.display = 'none';
        if (appLayout) appLayout.style.display = 'flex';
        if (mediaControls) mediaControls.style.display = 'flex';

        // Bind In-Call Header and Solo State
        const headerMeetingInfo = document.getElementById('headerMeetingInfo');
        const headerRoomId = document.getElementById('headerRoomId');
        if (headerMeetingInfo) headerMeetingInfo.style.display = 'flex';
        if (headerRoomId) headerRoomId.textContent = roomId;

        const inCallInviteBtn = document.getElementById('inCallInviteBtn');
        if (inCallInviteBtn) {
            inCallInviteBtn.style.display = 'inline-flex';
            inCallInviteBtn.onclick = () => window.copyMeetingLink(roomId);
        }

        const headerCopyBtn = document.getElementById('headerCopyBtn');
        if (headerCopyBtn) {
            headerCopyBtn.onclick = () => window.copyMeetingLink(roomId);
        }

        const soloRoomCodeDisplay = document.getElementById('soloRoomCodeDisplay');
        if (soloRoomCodeDisplay) soloRoomCodeDisplay.textContent = roomId;

        const soloCopyLinkBtn = document.getElementById('soloCopyLinkBtn');
        if (soloCopyLinkBtn) {
            soloCopyLinkBtn.onclick = () => {
                window.copyMeetingLink(roomId);
                const txt = document.getElementById('soloCopyBtnText');
                if (txt) {
                    const orig = txt.textContent;
                    txt.textContent = 'Copied to clipboard!';
                    setTimeout(() => { txt.textContent = orig; }, 2500);
                }
            };
        }

        const soloWhatsappBtn = document.getElementById('soloWhatsappBtn');
        if (soloWhatsappBtn) {
            soloWhatsappBtn.onclick = () => {
                const url = `${window.location.origin}/?room=${encodeURIComponent(roomId)}`;
                const text = encodeURIComponent(`Join my meeting on La-Vie Conference: ${url}`);
                window.open(`https://api.whatsapp.com/send?text=${text}`, '_blank');
            };
        }

        const closeSoloInviteBtn = document.getElementById('closeSoloInviteBtn');
        if (closeSoloInviteBtn) {
            closeSoloInviteBtn.onclick = () => {
                const card = document.getElementById('soloInviteCard');
                if (card) card.style.display = 'none';
            };
        }

        const soloInviteCard = document.getElementById('soloInviteCard');
        if (soloInviteCard) soloInviteCard.style.display = 'block';

        // Extract 2-letter luxury initials (e.g., Emmanuel Obinezu -> EO)
        const rawName = (state.userName || 'You').trim();
        const parts = rawName.split(/\s+/).filter(Boolean);
        const userInitials = parts.length > 1
            ? (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
            : (rawName.length >= 2 ? rawName.substring(0, 2).toUpperCase() : rawName.toUpperCase());

        const localAvatarLetter = document.getElementById('localAvatarLetter');
        if (localAvatarLetter) localAvatarLetter.textContent = userInitials;
        const localAvatarName = document.getElementById('localAvatarName');
        if (localAvatarName) localAvatarName.textContent = rawName;
        const localLabel = document.getElementById('localLabel');
        if (localLabel) localLabel.textContent = rawName + ' (You)';

        // Ensure local wrapper reflects initial state cleanly
        const localWrapper = document.getElementById('wrapper-local-camera');
        if (localWrapper) {
            if (!enableVideoAtStart) {
                localWrapper.classList.add('video-muted', 'video-off');
            } else {
                localWrapper.classList.remove('video-muted', 'video-off');
            }
            if (!enableMicAtStart) {
                localWrapper.classList.add('audio-muted');
            } else {
                localWrapper.classList.remove('audio-muted');
            }
        }

        if (meetingInfo) {
            meetingInfo.style.display = 'none';
        }

        const peerId = Math.random().toString(36).substring(2, 10);
        const fbToken = await getAuthToken();
        const headers = {};
        if (fbToken) { headers['Authorization'] = `Bearer ${fbToken}`; }

        let response = await fetch(`/token/${roomId}/${peerId}?name=${encodeURIComponent(state.userName)}`, { headers });
        if (!response.ok) {
            let errMsg = "Failed to connect to meeting room";
            let errDetail = null;
            try {
                const errData = await response.json();
                if (errData && errData.detail) {
                    errDetail = errData.detail;
                    errMsg = typeof errData.detail === 'string' ? errData.detail : (errData.detail.message || JSON.stringify(errData.detail));
                }
            } catch (_) {}
            if (response.status === 403 && errDetail && typeof errDetail === 'object' && errDetail.error === 'waiting_approval') {
                await showWebWaitingRoomOverlay(roomId, errDetail.title || 'Private Meeting', options);
                return;
            }
            throw new Error(errMsg);
        }
        const { token, is_admin, room_started_at, scheduled_time_ts } = await response.json();
        state.isAdmin = is_admin || false;
        startMeetingTimer(room_started_at, scheduled_time_ts);
        if (state.isAdmin) {
            _startHostWaitingMonitor(roomId);
        }

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

            const localWrapper = document.getElementById('wrapper-local-camera');
            if (localWrapper && state.currentRoom.localParticipant) {
                const isLocalSpeaking = state.activeSpeakerSet.has(state.currentRoom.localParticipant.identity);
                localWrapper.classList.toggle('speaking', isLocalSpeaking);
                const micStatusPill = document.getElementById('localMicStatusPill');
                if (micStatusPill) {
                    micStatusPill.classList.toggle('speaking-pill', isLocalSpeaking);
                }
            }

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

        // Track Muted / Unmuted / Local Track Lifecycle
        state.currentRoom.on(RoomEvent.TrackMuted, (pub, participant) => {
            if (participant === state.currentRoom?.localParticipant) {
                syncLocalMediaUI();
            } else if (pub.kind === 'video') {
                const wrapper = document.getElementById(`wrapper-${participant.identity}-${pub.source}`);
                if (wrapper) wrapper.classList.add('video-muted');
            }
        });

        state.currentRoom.on(RoomEvent.TrackUnmuted, (pub, participant) => {
            if (participant === state.currentRoom?.localParticipant) {
                syncLocalMediaUI();
            } else if (pub.kind === 'video') {
                const wrapper = document.getElementById(`wrapper-${participant.identity}-${pub.source}`);
                if (wrapper) wrapper.classList.remove('video-muted');
            }
        });

        state.currentRoom.on(RoomEvent.LocalTrackPublished, () => {
            syncLocalMediaUI();
        });

        state.currentRoom.on(RoomEvent.LocalTrackUnpublished, () => {
            syncLocalMediaUI();
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
        let wsUrl = state.livekitUrlFallback || "wss://lavie-prod-ngzo1pm2.livekit.cloud";
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
                if (localWrapper) {
                    localWrapper.classList.remove('video-muted', 'video-off');
                }
                if (toggleVideoBtn) {
                    toggleVideoBtn.classList.add('active');
                    toggleVideoBtn.classList.remove('muted-off');
                    const icon = toggleVideoBtn.querySelector('.material-symbols-outlined');
                    if (icon) icon.textContent = 'videocam';
                    const txt = toggleVideoBtn.querySelector('.btn-subtext') || toggleVideoBtn.querySelector('.btn-text');
                    if (txt) txt.textContent = 'Camera';
                }
            } else {
                await state.currentRoom.localParticipant.setCameraEnabled(false);
                state.isVideoEnabled = false;
                if (localWrapper) {
                    localWrapper.classList.add('video-muted', 'video-off');
                }
                if (toggleVideoBtn) {
                    toggleVideoBtn.classList.remove('active');
                    toggleVideoBtn.classList.add('muted-off');
                    const icon = toggleVideoBtn.querySelector('.material-symbols-outlined');
                    if (icon) icon.textContent = 'videocam_off';
                    const txt = toggleVideoBtn.querySelector('.btn-subtext') || toggleVideoBtn.querySelector('.btn-text');
                    if (txt) txt.textContent = 'Camera Off';
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
            if (localWrapper) {
                localWrapper.classList.add('video-muted', 'video-off');
            }
            if (toggleVideoBtn) {
                toggleVideoBtn.classList.remove('active');
                toggleVideoBtn.classList.add('muted-off');
                const icon = toggleVideoBtn.querySelector('.material-symbols-outlined');
                if (icon) icon.textContent = 'videocam_off';
                const txt = toggleVideoBtn.querySelector('.btn-subtext') || toggleVideoBtn.querySelector('.btn-text');
                if (txt) txt.textContent = 'Camera Off';
            }
        }

        // Publish Microphone
        try {
            const updateLocalMicUI = (isMuted) => {
                if (localWrapper) {
                    localWrapper.classList.toggle('audio-muted', isMuted);
                }
                const micIcon = document.getElementById('localMicStatusIcon');
                const micText = document.getElementById('localMicStatusText');
                const micPill = document.getElementById('localMicStatusPill');
                if (micIcon) micIcon.textContent = isMuted ? 'mic_off' : 'mic';
                if (micText) micText.textContent = isMuted ? 'Muted' : 'Mic active';
                if (micPill) micPill.classList.toggle('pill-muted', isMuted);
            };

            if (enableMicAtStart) {
                const micOptions = chosenMicId ? { deviceId: chosenMicId } : true;
                await state.currentRoom.localParticipant.setMicrophoneEnabled(true, micOptions, { dtx: true });
                state.isMicEnabled = true;
                updateLocalMicUI(false);
                if (toggleMicBtn) {
                    toggleMicBtn.classList.add('active');
                    toggleMicBtn.classList.remove('muted-off');
                    const icon = toggleMicBtn.querySelector('.material-symbols-outlined');
                    if (icon) icon.textContent = 'mic';
                    const txt = toggleMicBtn.querySelector('.btn-subtext') || toggleMicBtn.querySelector('.btn-text');
                    if (txt) txt.textContent = 'Mute';
                }
            } else {
                await state.currentRoom.localParticipant.setMicrophoneEnabled(false);
                state.isMicEnabled = false;
                updateLocalMicUI(true);
                if (toggleMicBtn) {
                    toggleMicBtn.classList.remove('active');
                    toggleMicBtn.classList.add('muted-off');
                    const icon = toggleMicBtn.querySelector('.material-symbols-outlined');
                    if (icon) icon.textContent = 'mic_off';
                    const txt = toggleMicBtn.querySelector('.btn-subtext') || toggleMicBtn.querySelector('.btn-text');
                    if (txt) txt.textContent = 'Muted';
                }
            }
        } catch (micErr) {
            console.warn("Microphone permission denied or unavailable:", micErr);
            micDenied = true;
            state.isMicEnabled = false;
            if (localWrapper) localWrapper.classList.add('audio-muted');
            const micPill = document.getElementById('localMicStatusPill');
            if (micPill) micPill.classList.add('pill-muted');
            if (toggleMicBtn) {
                toggleMicBtn.classList.remove('active');
                toggleMicBtn.classList.add('muted-off');
                const icon = toggleMicBtn.querySelector('.material-symbols-outlined');
                if (icon) icon.textContent = 'mic_off';
                const txt = toggleMicBtn.querySelector('.btn-subtext') || toggleMicBtn.querySelector('.btn-text');
                if (txt) txt.textContent = 'Muted';
            }
        }

        if (camDenied && micDenied) {
            showToast("Camera & Mic blocked. You joined in listen-only mode.", false);
        } else if (camDenied) {
            showToast("Camera blocked. Joined with microphone only.", false);
        } else if (micDenied) {
            showToast("Microphone blocked. Joined with camera only.", false);
        }

        syncLocalMediaUI();

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
        const rName = (participant.name || participant.identity || 'Guest').trim();
        const rParts = rName.split(/\s+/).filter(Boolean);
        const rInitials = rParts.length > 1
            ? (rParts[0][0] + rParts[rParts.length - 1][0]).toUpperCase()
            : (rName.length >= 2 ? rName.substring(0, 2).toUpperCase() : rName.toUpperCase());
        avatarDiv.innerHTML = `
            <div class="avatar-circle">
                <span>${rInitials}</span>
                <div class="avatar-pulse-ring"></div>
            </div>
            <div class="avatar-info-group">
                <span class="avatar-name">${rName}</span>
            </div>
        `;
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
    _stopWaitingIntervals();

    document.body.classList.remove('in-call');
    const headerMeetingInfo = document.getElementById('headerMeetingInfo');
    if (headerMeetingInfo) headerMeetingInfo.style.display = 'none';
    const inCallInviteBtn = document.getElementById('inCallInviteBtn');
    if (inCallInviteBtn) inCallInviteBtn.style.display = 'none';
    const soloInviteCard = document.getElementById('soloInviteCard');
    if (soloInviteCard) soloInviteCard.style.display = 'none';

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

    const totalCount = (local ? 1 : 0) + (state.currentRoom.remoteParticipants ? state.currentRoom.remoteParticipants.size : 0);
    const dockPeopleBadge = document.getElementById('dockPeopleBadge');
    if (dockPeopleBadge) dockPeopleBadge.textContent = totalCount;
    const peopleBtnSubtext = document.getElementById('peopleBtnSubtext');
    if (peopleBtnSubtext) peopleBtnSubtext.textContent = `People (${totalCount})`;

    const soloInviteCard = document.getElementById('soloInviteCard');
    if (soloInviteCard) {
        soloInviteCard.style.display = totalCount <= 1 ? 'block' : 'none';
    }
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

// ==========================================
// PRIVATE WAITING ROOM (ACCESS APPROVAL)
// ==========================================
let _waitingPollInterval = null;
let _hostWaitingMonitorInterval = null;

function _stopWaitingIntervals() {
    if (_waitingPollInterval) { clearInterval(_waitingPollInterval); _waitingPollInterval = null; }
    if (_hostWaitingMonitorInterval) { clearInterval(_hostWaitingMonitorInterval); _hostWaitingMonitorInterval = null; }
    const overlay = document.getElementById('webWaitingRoomOverlay');
    if (overlay) overlay.remove();
    const banner = document.getElementById('webHostKnockBanner');
    if (banner) banner.remove();
}

async function showWebWaitingRoomOverlay(roomId, title, joinOptions) {
    _stopWaitingIntervals();
    const appLayout = document.getElementById('appLayout');
    const joinScreen = document.getElementById('joinScreen');
    if (appLayout) appLayout.style.display = 'none';
    if (joinScreen) joinScreen.style.display = 'block';

    const fbToken = await getAuthToken();
    if (fbToken) {
        await fetch(`/api/room/${encodeURIComponent(roomId)}/knock`, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${fbToken}` }
        }).catch(() => {});
    }

    const overlay = document.createElement('div');
    overlay.id = 'webWaitingRoomOverlay';
    overlay.style.cssText = `
        position: fixed; inset: 0; z-index: 99995;
        background: rgba(7, 11, 25, 0.92); backdrop-filter: blur(18px);
        display: flex; align-items: center; justify-content: center; padding: 20px;
    `;
    overlay.innerHTML = `
        <div style="max-width:420px;width:100%;background:rgba(15,23,42,0.96);border:1px solid rgba(0,229,255,0.35);border-radius:24px;padding:32px;text-align:center;color:#fff;font-family:'Inter',sans-serif;">
            <div style="width:68px;height:68px;border-radius:50%;background:rgba(0,229,255,0.14);color:#00E5FF;display:flex;align-items:center;justify-content:center;margin:0 auto 18px auto;">
                <span class="material-symbols-outlined" style="font-size:34px;">admin_panel_settings</span>
            </div>
            <h2 style="margin:0 0 8px 0;font-size:21px;">${escapeHtml(title)}</h2>
            <div id="webWaitStatusBadge" style="display:inline-block;padding:5px 14px;border-radius:20px;background:rgba(245,158,11,0.15);color:#fbbf24;font-size:11.5px;font-weight:700;margin-bottom:14px;">
                WAITING FOR HOST APPROVAL
            </div>
            <p id="webWaitStatusText" style="color:rgba(255,255,255,0.7);font-size:14px;line-height:1.5;margin:0 0 24px 0;">
                Please wait — the host has been notified and will let you in shortly.
            </p>
            <button id="webLeaveWaitBtn" style="width:100%;padding:12px;border-radius:12px;border:1px solid rgba(255,255,255,0.2);background:transparent;color:#cbd5e1;font-weight:600;cursor:pointer;">
                Leave Waiting Room
            </button>
        </div>
    `;
    document.body.appendChild(overlay);

    document.getElementById('webLeaveWaitBtn').onclick = () => {
        _stopWaitingIntervals();
    };

    _waitingPollInterval = setInterval(async () => {
        try {
            const t = await getAuthToken();
            const r = await fetch(`/api/room/${encodeURIComponent(roomId)}/knock-status`, {
                headers: t ? { 'Authorization': `Bearer ${t}` } : {}
            });
            if (!r.ok) return;
            const res = await r.json();
            if (res.status === 'admitted' || res.status === 'open') {
                _stopWaitingIntervals();
                startCall(roomId, joinOptions);
            } else if (res.status === 'denied' || res.status === 'locked') {
                clearInterval(_waitingPollInterval);
                _waitingPollInterval = null;
                const badge = document.getElementById('webWaitStatusBadge');
                const txt = document.getElementById('webWaitStatusText');
                if (badge) { badge.textContent = res.status === 'locked' ? 'MEETING LOCKED' : 'ACCESS DECLINED'; badge.style.color = '#f87171'; }
                if (txt) txt.textContent = res.status === 'locked'
                    ? 'The host has locked this meeting.'
                    : 'The host declined your request to enter this private meeting.';
            }
        } catch (_) {}
    }, 2500);
}

async function _decideWebWaitingGuest(roomId, targetUid, action) {
    const t = await getAuthToken();
    await fetch(`/api/room/${encodeURIComponent(roomId)}/waiting-room/decision`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            ...(t ? { 'Authorization': `Bearer ${t}` } : {})
        },
        body: JSON.stringify({ target_uid: targetUid, action })
    }).catch(() => {});
}

async function _startHostWaitingMonitor(roomId) {
    if (_hostWaitingMonitorInterval) clearInterval(_hostWaitingMonitorInterval);

    const hostCtrl = document.getElementById('webHostWaitingControls');
    const toggleInput = document.getElementById('webWaitingRoomToggle');
    if (hostCtrl) hostCtrl.style.display = 'block';

    // Sync initial toggle state
    fetch(`/api/meeting/${encodeURIComponent(roomId)}/info`)
        .then(r => r.ok ? r.json() : null)
        .then(info => {
            if (info && toggleInput) toggleInput.checked = Boolean(info.requireApproval);
        }).catch(() => {});

    if (toggleInput) {
        toggleInput.onchange = async () => {
            const t = await getAuthToken();
            const r = await fetch('/api/room/waiting-room/toggle', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    ...(t ? { 'Authorization': `Bearer ${t}` } : {})
                },
                body: JSON.stringify({ room_id: roomId, enabled: toggleInput.checked })
            });
            if (r.ok) {
                showToast(toggleInput.checked ? 'Private Waiting Room Enabled' : 'Waiting Room Disabled');
            }
        };
    }

    const pollHostQueue = async () => {
        try {
            const t = await getAuthToken();
            if (!t) return;
            const r = await fetch(`/api/room/${encodeURIComponent(roomId)}/waiting-room`, {
                headers: { 'Authorization': `Bearer ${t}` }
            });
            if (!r.ok) return;
            const data = await r.json();
            const waiting = data.waiting || [];
            _renderWebWaitingQueue(roomId, waiting);
        } catch (_) {}
    };

    pollHostQueue();
    _hostWaitingMonitorInterval = setInterval(pollHostQueue, 2500);
}

function _renderWebWaitingQueue(roomId, waiting) {
    const section = document.getElementById('webWaitingRoomSection');
    let banner = document.getElementById('webHostKnockBanner');

    if (!waiting || waiting.length === 0) {
        if (section) { section.style.display = 'none'; section.innerHTML = ''; }
        if (banner) banner.remove();
        return;
    }

    if (section) {
        section.style.display = 'block';
        section.innerHTML = `
            <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:8px;">
                <span style="color:#fbbf24;font-size:12px;font-weight:700;">WAITING ROOM (${waiting.length})</span>
                <button id="webAdmitAllBtn" style="background:rgba(0,255,163,0.2);color:#00FFA3;border:none;border-radius:8px;padding:3px 8px;font-size:11px;font-weight:700;cursor:pointer;">Admit All</button>
            </div>
            ${waiting.map(g => `
                <div style="display:flex;align-items:center;justify-content:space-between;gap:6px;padding:4px 0;">
                    <span style="color:#fff;font-size:13px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${escapeHtml(g.name)}</span>
                    <div style="display:flex;gap:4px;">
                        <button class="web-deny-btn" data-uid="${escapeHtml(g.uid)}" style="background:transparent;color:#f87171;border:1px solid rgba(248,113,113,0.4);border-radius:6px;padding:3px 7px;font-size:11px;cursor:pointer;">Deny</button>
                        <button class="web-admit-btn" data-uid="${escapeHtml(g.uid)}" style="background:#00FFA3;color:#070B19;border:none;border-radius:6px;padding:3px 8px;font-size:11px;font-weight:700;cursor:pointer;">Admit</button>
                    </div>
                </div>
            `).join('')}
        `;

        const admitAllBtn = document.getElementById('webAdmitAllBtn');
        if (admitAllBtn) admitAllBtn.onclick = async () => { await _decideWebWaitingGuest(roomId, '', 'admit_all'); _renderWebWaitingQueue(roomId, []); };
        section.querySelectorAll('.web-admit-btn').forEach(b => {
            b.onclick = async () => { await _decideWebWaitingGuest(roomId, b.dataset.uid, 'admit'); _renderWebWaitingQueue(roomId, waiting.filter(x => x.uid !== b.dataset.uid)); };
        });
        section.querySelectorAll('.web-deny-btn').forEach(b => {
            b.onclick = async () => { await _decideWebWaitingGuest(roomId, b.dataset.uid, 'deny'); _renderWebWaitingQueue(roomId, waiting.filter(x => x.uid !== b.dataset.uid)); };
        });
    }

    // Floating top toast banner for quick admission
    const first = waiting[0];
    if (!banner) {
        banner = document.createElement('div');
        banner.id = 'webHostKnockBanner';
        banner.style.cssText = `
            position: fixed; top: 72px; left: 50%; transform: translateX(-50%); z-index: 99990;
            background: rgba(15, 23, 42, 0.96); border: 1px solid rgba(251, 191, 36, 0.65);
            border-radius: 14px; padding: 10px 14px; display: flex; align-items: center; gap: 12px;
            box-shadow: 0 12px 32px rgba(0,0,0,0.45); color: #fff; font-family: 'Inter', sans-serif;
        `;
        document.body.appendChild(banner);
    }
    banner.innerHTML = `
        <span style="font-size:13px;">🔒 <strong>${escapeHtml(first.name)}</strong> wants to join${waiting.length > 1 ? ` (+${waiting.length - 1})` : ''}</span>
        <button id="webBannerDeny" style="background:transparent;color:#f87171;border:1px solid rgba(248,113,113,0.4);border-radius:8px;padding:4px 10px;font-size:12px;font-weight:600;cursor:pointer;">Deny</button>
        <button id="webBannerAdmit" style="background:#00FFA3;color:#070B19;border:none;border-radius:8px;padding:5px 12px;font-size:12px;font-weight:700;cursor:pointer;">Admit</button>
    `;
    document.getElementById('webBannerAdmit').onclick = async () => { await _decideWebWaitingGuest(roomId, first.uid, 'admit'); _renderWebWaitingQueue(roomId, waiting.filter(x => x.uid !== first.uid)); };
    document.getElementById('webBannerDeny').onclick = async () => { await _decideWebWaitingGuest(roomId, first.uid, 'deny'); _renderWebWaitingQueue(roomId, waiting.filter(x => x.uid !== first.uid)); };
}
