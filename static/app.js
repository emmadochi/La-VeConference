// ==========================================
// LA-VIE CONFERENCE — APPLICATION ENTRY POINT
// ==========================================
import { state } from "./modules/state.js";
import { 
    showToast, 
    copyTextToClipboard, 
    getMeetingShareUrl, 
    copyMeetingLink, 
    copyMeetingCode,
    formatFriendlyErrorMessage
} from "./modules/utils.js";
import { 
    updateCameraDevicesList, 
    updateAudioDevicesList, 
    selectCameraDevice, 
    selectAudioInputDevice, 
    selectAudioOutputDevice, 
    populateSettingsDevices, 
    initDeviceListeners,
    showAudioOutputQuickPick,
    updateAudioOutputButtonState,
    toggleDataSaverMode
} from "./modules/devices.js";
import { toggleCaptions } from "./modules/captions.js";
import { startRecording, stopRecording, saveRecording } from "./modules/recording.js";
import { initChatListeners } from "./modules/chat.js";
import { 
    broadcast, 
    renderPollsUI, 
    renderQaUI, 
    initPollsAndQaListeners 
} from "./modules/polls.js";
import { 
    startCall, 
    leaveCall, 
    togglePin, 
    toggleWrapperFullscreen, 
    updateVideoGridClass,
    muteParticipant,
    kickParticipant,
    syncLocalMediaUI 
} from "./modules/webrtc.js";
import { openGreenRoom, closeGreenRoom } from "./modules/greenroom.js";
import { getAuthToken } from "./auth.js";
import { BackgroundProcessor, supportsBackgroundProcessors } from "https://esm.sh/@livekit/track-processors@0.7.2";
import { KrispNoiseFilter } from "https://esm.sh/@livekit/krisp-noise-filter@0.1.3";
import * as LivekitClient from "https://esm.sh/livekit-client@2.20.1";

const { Track } = LivekitClient;

// ==========================================
// DOM REFERENCES
// ==========================================
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

const leaveCallBtn = document.getElementById('leaveCallBtn');
const toggleMicBtn = document.getElementById('toggleMicBtn');
const toggleVideoBtn = document.getElementById('toggleVideoBtn');
const toggleScreenBtn = document.getElementById('toggleScreenBtn');
const toggleRecordBtn = document.getElementById('toggleRecordBtn');

const flipCameraBtn = document.getElementById('flipCameraBtn');
const flipCameraBtnText = document.getElementById('flipCameraBtnText');
const cameraListContainer = document.getElementById('cameraListContainer');
const audioDevicesBtn = document.getElementById('audioDevicesBtn');
const audioListContainer = document.getElementById('audioListContainer');
const speakerDevicesBtn = document.getElementById('speakerDevicesBtn');
const speakerListContainer = document.getElementById('speakerListContainer');
const audioOutputBtn = document.getElementById('audioOutputBtn');

const toggleChatBtn = document.getElementById('navChatBtn') || document.getElementById('toggleChatBtn');
const togglePeopleBtn = document.getElementById('navPeopleBtn') || document.getElementById('togglePeopleBtn');
const toggleWhiteboardBtn = document.getElementById('navWhiteboardBtn') || document.getElementById('toggleWhiteboardBtn');
const togglePollsBtn = document.getElementById('navPollsBtn') || document.getElementById('togglePollsBtn');
const navQaBtn = document.getElementById('navQaBtn');

const chatSidebar = document.querySelector('.chat-sidebar:not(.people-sidebar)');
const peopleSidebar = document.getElementById('peopleSidebar');
const pollQaSidebar = document.getElementById('pollQaSidebar');

const toggleReactBtn = document.getElementById('toggleReactBtn');
const emojiPopover = document.getElementById('emojiPopover');
const toggleHandBtn = document.getElementById('toggleHandBtn');
const toggleEffectsBtn = document.getElementById('toggleEffectsBtn');
const effectsModal = document.getElementById('effectsModal');
const closeEffectsBtn = document.getElementById('closeEffectsBtn');
const effectsGrid = document.getElementById('effectsGrid');
const toggleNoiseBtn = document.getElementById('toggleNoiseBtn');

const mainColumn = document.getElementById('mainColumn');
const whiteboardContainer = document.getElementById('whiteboardContainer');

// ==========================================
// BOOTSTRAP & INITIALIZATION
// ==========================================
document.addEventListener('DOMContentLoaded', async () => {
    initDeviceListeners();
    initChatListeners();
    initPollsAndQaListeners();

    // URL parameter parsing (?room=...) OR path (/meeting/{id}, /room/{id})
    const params = new URLSearchParams(window.location.search);
    let roomParam = params.get('room');
    if (!roomParam) {
        const parts = window.location.pathname.split('/').filter(Boolean);
        if (parts.length >= 2 && ['meeting', 'room', 'conf'].includes(parts[0])) {
            roomParam = parts[1];
        }
    }

    if (roomParam) {
        if (roomIdInput) {
            roomIdInput.value = roomParam;
            if (joinBtn) {
                joinBtn.disabled = false;
                joinBtn.classList.add('active');
            }
        }
        await checkAndPresentScheduledLobby(roomParam);
    }
});

function buildGoogleCalendarTemplateUrl(title, startMs, roomUrl) {
    const start = new Date(startMs);
    const end = new Date(startMs + 60 * 60 * 1000);
    const fmt = (d) => d.toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z';
    const q = new URLSearchParams({
        action: 'TEMPLATE',
        text: title || 'La-Vie Conference Meeting',
        dates: `${fmt(start)}/${fmt(end)}`,
        details: `Join La-Vie Conference:\n${roomUrl}\n\nThis meeting is End-to-End Encrypted.`,
        location: roomUrl,
    });
    return `https://calendar.google.com/calendar/render?${q.toString()}`;
}

async function checkAndPresentScheduledLobby(roomId) {
    try {
        const cleanId = roomId.split('#')[0].trim();
        const fbToken = window.getAuthToken ? await window.getAuthToken().catch(() => null) : null;
        const headers = fbToken ? { 'Authorization': `Bearer ${fbToken}` } : {};
        const resp = await fetch(`/api/meeting/${encodeURIComponent(cleanId)}/info`, { headers });
        if (resp.ok) {
            const info = await resp.json();
            if (info && info.isFutureScheduled && info.scheduledTimeTs) {
                showWebUpcomingInviteModal(info, cleanId);
                return;
            }
        }
    } catch (e) {
        console.warn('Scheduled lobby lookup skipped:', e);
    }
    initiateJoinFlow(roomId);
}

function showWebUpcomingInviteModal(info, cleanRoomId) {
    const existing = document.getElementById('webUpcomingInviteOverlay');
    if (existing) existing.remove();

    const schedMs = info.scheduledTimeTs * 1000;
    const schedDate = new Date(schedMs);
    const fullUrl = window.location.href;
    const calUrl = buildGoogleCalendarTemplateUrl(info.title, schedMs, fullUrl);

    const overlay = document.createElement('div');
    overlay.id = 'webUpcomingInviteOverlay';
    overlay.style.cssText = `
        position: fixed; inset: 0; z-index: 99990;
        background: rgba(7, 11, 25, 0.85); backdrop-filter: blur(16px);
        display: flex; align-items: center; justify-content: center; padding: 20px;
    `;

    overlay.innerHTML = `
        <div style="
            max-width: 440px; width: 100%; background: rgba(15, 23, 42, 0.96);
            border: 1px solid rgba(0, 229, 255, 0.35); border-radius: 24px;
            padding: 28px; color: #fff; box-shadow: 0 24px 60px rgba(0,0,0,0.6);
            font-family: 'Inter', sans-serif; text-align: center;
        ">
            <div style="display:inline-flex;align-items:center;gap:6px;padding:6px 14px;border-radius:20px;background:rgba(0,229,255,0.12);color:#00E5FF;font-size:12px;font-weight:700;margin-bottom:14px;">
                <span>UPCOMING SCHEDULED MEETING</span>
            </div>
            <h2 style="margin:0 0 8px 0;font-size:22px;font-weight:700;">${(info.title || 'La-Vie Conference').replace(/</g, '&lt;')}</h2>
            <p style="margin:0 0 16px 0;color:rgba(255,255,255,0.65);font-size:13.5px;">
                Hosted by <strong style="color:#fff;">${(info.hostName || 'La-Vie Host').replace(/</g, '&lt;')}</strong>
            </p>
            <div style="background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.1);border-radius:16px;padding:16px;margin-bottom:20px;">
                <div style="font-size:14px;color:rgba(255,255,255,0.85);margin-bottom:6px;">
                    ${schedDate.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' })} • ${schedDate.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })}
                </div>
                <div id="webInviteCountdown" style="font-size:24px;font-weight:800;color:#00FFA3;letter-spacing:1px;">--:--</div>
            </div>
            <div style="display:flex;flex-direction:column;gap:10px;margin-bottom:14px;">
                <div style="display:flex;gap:8px;align-items:center;">
                    <select id="webReminderSelect" style="flex:1;background:#1e293b;color:#fff;border:1px solid rgba(255,255,255,0.2);border-radius:12px;padding:10px 12px;font-size:13px;">
                        <option value="15">Remind 15 mins before</option>
                        <option value="30">Remind 30 mins before</option>
                        <option value="60">Remind 1 hour before</option>
                        <option value="0">Remind at start time</option>
                    </select>
                    <button id="webSetReminderBtn" style="background:#00E5FF;color:#070B19;border:none;border-radius:12px;padding:11px 16px;font-weight:700;font-size:13px;cursor:pointer;">
                        🔔 Set Push Reminder
                    </button>
                </div>
                <a href="${calUrl}" target="_blank" rel="noopener" style="
                    display:flex;align-items:center;justify-content:center;gap:8px;
                    background:rgba(255,255,255,0.08);color:#fff;border:1px solid rgba(255,255,255,0.18);
                    border-radius:12px;padding:12px;font-weight:600;font-size:14px;text-decoration:none;
                ">
                    📅 Add to Google Calendar
                </a>
            </div>
            <div style="display:flex;gap:10px;">
                <button id="webCloseInviteBtn" style="flex:1;background:transparent;color:rgba(255,255,255,0.6);border:1px solid rgba(255,255,255,0.15);border-radius:12px;padding:11px;font-weight:600;cursor:pointer;">
                    Dismiss
                </button>
                <button id="webEnterEarlyBtn" style="flex:2;background:rgba(0,255,163,0.16);color:#00FFA3;border:1px solid rgba(0,255,163,0.4);border-radius:12px;padding:11px;font-weight:700;cursor:pointer;">
                    Enter Waiting Stage
                </button>
            </div>
        </div>
    `;
    document.body.appendChild(overlay);

    const countdownEl = document.getElementById('webInviteCountdown');
    const tick = () => {
        const diffSec = Math.max(0, Math.floor((schedMs - Date.now()) / 1000));
        if (diffSec === 0) {
            if (countdownEl) countdownEl.textContent = 'Starting Now!';
            clearInterval(timer);
            return;
        }
        const h = Math.floor(diffSec / 3600);
        const m = Math.floor((diffSec % 3600) / 60);
        const s = diffSec % 60;
        const pad = (n) => String(n).padStart(2, '0');
        if (countdownEl) {
            countdownEl.textContent = h > 0 ? `Starts in ${h}h ${pad(m)}m ${pad(s)}s` : `Starts in ${pad(m)}m ${pad(s)}s`;
        }
    };
    tick();
    const timer = setInterval(tick, 1000);

    document.getElementById('webCloseInviteBtn').onclick = () => {
        clearInterval(timer);
        overlay.remove();
    };
    document.getElementById('webEnterEarlyBtn').onclick = () => {
        clearInterval(timer);
        overlay.remove();
        initiateJoinFlow(cleanRoomId);
    };
    document.getElementById('webSetReminderBtn').onclick = async () => {
        const mins = parseInt(document.getElementById('webReminderSelect').value || '15', 10);
        const user = window.firebaseAuth && window.firebaseAuth.currentUser;
        if (!user) {
            showToast('Please log in so we can send you a push reminder.');
            if (window.openAuthModal) window.openAuthModal(true);
            return;
        }
        try {
            const token = await getAuthToken();
            const r = await fetch(`/api/meeting/${encodeURIComponent(cleanRoomId)}/reminder`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    ...(token ? { 'Authorization': `Bearer ${token}` } : {})
                },
                body: JSON.stringify({ reminderMinutes: mins })
            });
            if (r.ok) {
                showToast(`🔔 Push reminder set for ${mins === 0 ? 'start time' : mins + ' mins before'}!`);
                document.getElementById('webSetReminderBtn').textContent = '✓ Reminder Set';
            } else {
                showToast('Could not save reminder. Please try again.', true);
            }
        } catch (err) {
            showToast('Network error saving reminder.', true);
        }
    };
}

// Join Button Enable/Disable
if (roomIdInput && joinBtn) {
    roomIdInput.addEventListener('input', (e) => {
        const hasText = e.target.value.trim().length > 0;
        joinBtn.disabled = !hasText;
        joinBtn.classList.toggle('active', hasText);
    });

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
}

// New Meeting Dropdown
if (newMeetingBtn) {
    newMeetingBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        const user = window.firebaseAuth && window.firebaseAuth.currentUser;
        if (!user) {
            if (window.openAuthModal) { window.openAuthModal(true); }
            else { alert("Please log in to start a new meeting."); }
            return;
        }
        if (newMeetingDropdown) {
            const isVisible = newMeetingDropdown.style.display === 'block';
            newMeetingDropdown.style.display = isVisible ? 'none' : 'block';
        }
    });
}
window.addEventListener('click', () => { 
    if (newMeetingDropdown) newMeetingDropdown.style.display = 'none'; 
});

if (scheduleMeetingBtn && scheduleModal) {
    scheduleMeetingBtn.addEventListener('click', () => { scheduleModal.style.display = 'flex'; });
}
if (instantMeetingBtn) {
    instantMeetingBtn.addEventListener('click', () => { initiateJoinFlow(generateRoomCode(), true); });
}

function generateRoomCode() {
    return 'la-vie-' + Date.now().toString().substring(7);
}

// ==========================================
// JOIN FLOW & ACTIVE MEETING INTERCEPT
// ==========================================
export async function initiateJoinFlow(roomId, isHost = false) {
    try {
        const url = new URL(roomId);
        const urlRoom = url.searchParams.get('room');
        if (urlRoom) roomId = urlRoom;
    } catch(e) {}

    const cleanRoomId = roomId.trim();
    if (!cleanRoomId) return;

    state.pendingRoomId = cleanRoomId;
    state.isHost = isHost;

    // STEP 0: Wait for Firebase Auth persistence check if not yet ready
    let user = window.firebaseAuth && window.firebaseAuth.currentUser;
    if (!user && window.waitForAuthInit) {
        try {
            user = await Promise.race([
                window.waitForAuthInit(),
                new Promise(resolve => setTimeout(() => resolve(window.firebaseAuth ? window.firebaseAuth.currentUser : null), 2500))
            ]);
        } catch (_) {
            user = window.firebaseAuth ? window.firebaseAuth.currentUser : null;
        }
    }

    // REQUIRE LOGIN: No one can join without logging in!
    if (!user) {
        if (preJoinModal) preJoinModal.style.display = 'none';
        showToast("Please log in or sign up to join the meeting.");
        if (window.openAuthModal) {
            window.openAuthModal(true);
        }
        return;
    }

    // STEP 0: ACTIVE MEETING CONFLICT CHECK (Feature 4)
    if (state.currentRoom && (state.currentRoom.state === 'connected' || state.currentRoom.state === 'connecting')) {
        if (state.currentRoom.name === cleanRoomId) {
            showToast("You are already in this meeting!");
            return;
        }

        const conflictModal = document.getElementById('activeMeetingConflictModal');
        const currentRoomSpan = document.getElementById('conflictCurrentRoomId');
        const targetRoomSpan = document.getElementById('conflictTargetRoomId');
        const leaveAndJoinBtn = document.getElementById('leaveAndJoinBtn');
        const cancelConflictBtn = document.getElementById('cancelConflictBtn');
        const closeConflictModalBtn = document.getElementById('closeConflictModalBtn');

        if (conflictModal) {
            if (currentRoomSpan) currentRoomSpan.textContent = state.currentRoom.name;
            if (targetRoomSpan) targetRoomSpan.textContent = cleanRoomId;
            conflictModal.style.display = 'flex';

            const closeConflict = () => { conflictModal.style.display = 'none'; };
            if (cancelConflictBtn) cancelConflictBtn.onclick = closeConflict;
            if (closeConflictModalBtn) closeConflictModalBtn.onclick = closeConflict;

            if (leaveAndJoinBtn) {
                leaveAndJoinBtn.onclick = () => {
                    closeConflict();
                    leaveCall(); // Cleanly disconnect old room
                    proceedWithJoin(cleanRoomId, isHost, user);
                };
            }
            return;
        }
    }

    proceedWithJoin(cleanRoomId, isHost, user);
}
window.initiateJoinFlow = initiateJoinFlow;

function proceedWithJoin(roomId, isHost = false, user = null) {
    state.pendingRoomId = roomId;
    state.isHost = isHost;
    if (!user) {
        user = window.firebaseAuth && window.firebaseAuth.currentUser;
    }

    if (!user) {
        // Enforce login requirement: no anonymous joining
        if (preJoinModal) preJoinModal.style.display = 'none';
        showToast("Please log in to join the meeting.");
        if (window.openAuthModal) {
            window.openAuthModal(true);
        }
        return;
    }

    // Dismiss guest name modal if it was visible
    if (preJoinModal) preJoinModal.style.display = 'none';

    // Set authenticated user's name
    state.userName = user.displayName || (user.email ? user.email.split('@')[0] : "User");

    // STEP 1: PRE-CALL GREEN ROOM (Feature 1)
    openGreenRoom(state.pendingRoomId, state.userName, (options) => {
        startCall(state.pendingRoomId, options);
    }, null, isHost);
}

if (preJoinSubmitBtn) {
    preJoinSubmitBtn.addEventListener('click', () => {
        const user = window.firebaseAuth && window.firebaseAuth.currentUser;
        if (!user) {
            if (preJoinModal) preJoinModal.style.display = 'none';
            showToast("Please log in to join the meeting.");
            if (window.openAuthModal) window.openAuthModal(true);
            return;
        }
        if (userNameInput && userNameInput.value.trim()) {
            state.userName = userNameInput.value.trim();
        } else {
            state.userName = user.displayName || (user.email ? user.email.split('@')[0] : "User");
        }
        if (preJoinModal) preJoinModal.style.display = 'none';

        // STEP 1: PRE-CALL GREEN ROOM (Feature 1)
        openGreenRoom(state.pendingRoomId, state.userName, (options) => {
            startCall(state.pendingRoomId, options);
        }, null, state.isHost);
    });
}

// Automatically resume pending meeting join after user signs in / logs in
window.addEventListener('authStateChanged', (e) => {
    const user = e.detail && e.detail.user;
    if (user) {
        if (preJoinModal) preJoinModal.style.display = 'none';
        if (state.pendingRoomId && (!state.currentRoom || state.currentRoom.state !== 'connected')) {
            const greenRoomOverlay = document.getElementById('greenRoomOverlay');
            if (!greenRoomOverlay || greenRoomOverlay.style.display === 'none') {
                proceedWithJoin(state.pendingRoomId, state.isHost, user);
            }
        }
    }
});

// ==========================================
// MEDIA CONTROLS
// ==========================================
let _isTogglingMic = false;
let _isTogglingVideo = false;

if (toggleMicBtn) {
    toggleMicBtn.addEventListener('click', async () => {
        const lp = state.currentRoom?.localParticipant;
        if (!lp || _isTogglingMic) return;
        _isTogglingMic = true;
        toggleMicBtn.disabled = true;
        try {
            const micPub = lp.getTrackPublication(Track.Source.Microphone);
            const currentlyLive = Boolean(lp.isMicrophoneEnabled && micPub && !micPub.isMuted);
            const targetEnable = !currentlyLive;
            if (targetEnable) {
                const micOpts = state.activeAudioInputDeviceId ? { deviceId: state.activeAudioInputDeviceId } : true;
                await lp.setMicrophoneEnabled(true, micOpts, { dtx: true });
            } else {
                await lp.setMicrophoneEnabled(false);
            }
        } catch (err) {
            console.warn("Microphone toggle failed:", err);
            showToast("Could not toggle microphone. Check browser permissions.", true);
        } finally {
            syncLocalMediaUI();
            _isTogglingMic = false;
            toggleMicBtn.disabled = false;
        }
    });
}

if (toggleVideoBtn) {
    toggleVideoBtn.addEventListener('click', async () => {
        const lp = state.currentRoom?.localParticipant;
        if (!lp || _isTogglingVideo) return;
        _isTogglingVideo = true;
        toggleVideoBtn.disabled = true;
        try {
            const camPub = lp.getTrackPublication(Track.Source.Camera);
            const currentlyLive = Boolean(lp.isCameraEnabled && camPub && !camPub.isMuted);
            const targetEnable = !currentlyLive;
            if (targetEnable) {
                const camOpts = state.activeCameraDeviceId ? { deviceId: state.activeCameraDeviceId } : true;
                await lp.setCameraEnabled(true, camOpts);
            } else {
                await lp.setCameraEnabled(false);
            }
        } catch (err) {
            console.warn("Camera toggle failed:", err);
            showToast("Could not toggle camera. Check browser permissions.", true);
        } finally {
            syncLocalMediaUI();
            _isTogglingVideo = false;
            toggleVideoBtn.disabled = false;
        }
    });
}

const isMobileDevice = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent) || (navigator.maxTouchPoints && navigator.maxTouchPoints > 2);
if (isMobileDevice && toggleScreenBtn) { toggleScreenBtn.style.display = 'none'; }

if (toggleScreenBtn) {
    toggleScreenBtn.addEventListener('click', async () => {
        if (!state.currentRoom) return;
        if (!state.isScreenSharing) {
            try {
                await state.currentRoom.localParticipant.setScreenShareEnabled(true);
                state.isScreenSharing = true;
                toggleScreenBtn.classList.add('active');
                const icon = toggleScreenBtn.querySelector('.material-symbols-outlined');
                const txt = toggleScreenBtn.querySelector('.btn-text');
                if (icon) icon.textContent = 'cancel_presentation';
                if (txt) txt.textContent = 'Stop';
            } catch (err) {
                console.error("Error sharing screen:", err);
                const friendly = formatFriendlyErrorMessage(err);
                if (friendly) {
                    showToast(friendly, true);
                }
            }
        } else {
            await state.currentRoom.localParticipant.setScreenShareEnabled(false);
            state.isScreenSharing = false;
            toggleScreenBtn.classList.remove('active');
            const icon = toggleScreenBtn.querySelector('.material-symbols-outlined');
            const txt = toggleScreenBtn.querySelector('.btn-text');
            if (icon) icon.textContent = 'present_to_all';
            if (txt) txt.textContent = 'Share';
        }
    });
}

if (toggleRecordBtn) {
    toggleRecordBtn.addEventListener('click', async () => {
        if (state.mediaRecorder && state.mediaRecorder.state !== 'inactive') {
            stopRecording();
            saveRecording();
        } else {
            await startRecording();
        }
    });
}

// Device Accordions
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

// Audio output quick-switch button (controls bar)
if (audioOutputBtn) {
    audioOutputBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        showAudioOutputQuickPick();
    });
}

// Local Video Controls
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

// Fullscreen
function toggleAppFullscreen() {
    const fsEl = document.fullscreenElement || document.webkitFullscreenElement || document.mozFullScreenElement || document.msFullscreenElement;
    if (fsEl) {
        if (document.exitFullscreen) document.exitFullscreen().catch(console.error);
        else if (document.webkitExitFullscreen) document.webkitExitFullscreen();
    } else {
        const docEl = document.documentElement;
        if (docEl.requestFullscreen) docEl.requestFullscreen().catch(console.error);
        else if (docEl.webkitRequestFullscreen) docEl.webkitRequestFullscreen();
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

// Theme Toggle
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

// Reactions & Hand Raise
if (toggleReactBtn) {
    toggleReactBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        const isShowing = emojiPopover.style.display === 'flex';
        emojiPopover.style.display = isShowing ? 'none' : 'flex';
        toggleReactBtn.classList.toggle('active', !isShowing);
    });

    document.addEventListener('click', (e) => {
        if (!toggleReactBtn.contains(e.target) && !emojiPopover.contains(e.target)) {
            emojiPopover.style.display = 'none';
            toggleReactBtn.classList.remove('active');
        }
    });
}

document.querySelectorAll('.emoji-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
        const emoji = e.target.textContent.trim();
        if (emojiPopover) emojiPopover.style.display = 'none';
        const mobileEmojiPopover = document.getElementById('mobileEmojiPopover');
        if (mobileEmojiPopover) mobileEmojiPopover.style.display = 'none';
        if (toggleReactBtn) toggleReactBtn.classList.remove('active');
        closeMoreDrawer();
        closeMobileSheet();
        if (state.currentRoom && state.currentRoom.state === 'connected') {
            const payload = JSON.stringify({ type: 'reaction', emoji: emoji, senderId: state.currentRoom.localParticipant.identity });
            const data = new TextEncoder().encode(payload);
            state.currentRoom.localParticipant.publishData(data, { reliable: true });
            const wrapper = document.getElementById('wrapper-local-camera');
            if (wrapper) {
                const emojiEl = document.createElement('div');
                emojiEl.className = 'floating-emoji';
                emojiEl.textContent = emoji;
                wrapper.appendChild(emojiEl);
                setTimeout(() => { if (emojiEl.parentNode) emojiEl.remove(); }, 2500);
            }
        }
        showToast('Reaction sent: ' + emoji);
    });
});

if (toggleHandBtn) {
    toggleHandBtn.addEventListener('click', () => {
        if (!state.currentRoom || state.currentRoom.state !== 'connected') return;
        state.isHandRaised = !state.isHandRaised;
        toggleHandBtn.classList.toggle('active', state.isHandRaised);
        const payload = JSON.stringify({ type: 'raise_hand', state: state.isHandRaised, senderId: state.currentRoom.localParticipant.identity });
        const data = new TextEncoder().encode(payload);
        state.currentRoom.localParticipant.publishData(data, { reliable: true });
        
        const localWrapper = document.getElementById('wrapper-local-camera');
        if (localWrapper) {
            let badge = localWrapper.querySelector('.hand-badge');
            if (state.isHandRaised && !badge) {
                badge = document.createElement('div');
                badge.className = 'hand-badge';
                badge.textContent = '✋';
                localWrapper.appendChild(badge);
            } else if (!state.isHandRaised && badge) {
                badge.remove();
            }
        }
        showToast(state.isHandRaised ? 'Hand raised' : 'Hand lowered');
    });
}

// Background Effects
if (toggleEffectsBtn && effectsModal) {
    toggleEffectsBtn.addEventListener('click', () => { effectsModal.style.display = 'flex'; });
    if (closeEffectsBtn) closeEffectsBtn.addEventListener('click', () => { effectsModal.style.display = 'none'; });
}

if (effectsGrid) {
    const options = effectsGrid.querySelectorAll('.effect-option');
    options.forEach(option => {
        option.addEventListener('click', async () => {
            if (!state.backgroundProcessor || !state.currentRoom) {
                showToast("Background effects not supported on this device.", true);
                return;
            }
            options.forEach(o => o.classList.remove('active'));
            option.classList.add('active');
            const effect = option.getAttribute('data-effect');
            try {
                if (effect === 'none') { await state.backgroundProcessor.switchTo({ mode: 'disabled' }); }
                else if (effect === 'blur') { await state.backgroundProcessor.switchTo({ mode: 'background-blur', blurRadius: 15 }); }
                else { await state.backgroundProcessor.switchTo({ mode: 'virtual-background', imagePath: `/static/assets/${effect}.png` }); }
            } catch(e) {
                console.error("Error switching background effect", e);
                showToast("Failed to apply effect.", true);
            }
        });
    });
}

if (toggleNoiseBtn) {
    toggleNoiseBtn.addEventListener('click', async () => {
        if (!state.currentRoom || !state.krispFilter) { showToast("Noise cancellation not available.", true); return; }
        const audioTrack = state.currentRoom.localParticipant.getTrackPublication(Track.Source.Microphone)?.audioTrack;
        if (!audioTrack) return;
        state.isNoiseCancellationEnabled = !state.isNoiseCancellationEnabled;
        toggleNoiseBtn.classList.toggle('active', state.isNoiseCancellationEnabled);
        try {
            if (state.isNoiseCancellationEnabled) {
                await audioTrack.setProcessor(state.krispFilter);
                showToast("AI Noise Cancellation Enabled");
            } else {
                await audioTrack.stopProcessor();
                showToast("AI Noise Cancellation Disabled");
            }
        } catch(e) {
            console.error("Error toggling noise filter", e);
            state.isNoiseCancellationEnabled = !state.isNoiseCancellationEnabled;
            toggleNoiseBtn.classList.toggle('active', state.isNoiseCancellationEnabled);
            showToast("Failed to toggle noise cancellation.", true);
        }
    });
}

// Whiteboard
if (toggleWhiteboardBtn) {
    toggleWhiteboardBtn.addEventListener('click', () => {
        if (!state.currentRoom || state.currentRoom.state !== 'connected') return;
        state.isWhiteboardActive = !state.isWhiteboardActive;
        toggleWhiteboardBtn.classList.toggle('active', state.isWhiteboardActive);
        if (state.isWhiteboardActive) {
            if (mainColumn) mainColumn.classList.add('with-whiteboard');
            if (whiteboardContainer) {
                whiteboardContainer.classList.add('active');
                if (!whiteboardContainer.querySelector('iframe')) {
                    const iframe = document.createElement('iframe');
                    iframe.src = `https://wbo.ophir.dev/boards/lavie-${state.currentRoom.name}`;
                    whiteboardContainer.appendChild(iframe);
                }
            }
            broadcast({ type: 'whiteboard_toggle', state: true, senderId: state.currentRoom.localParticipant.identity });
        } else {
            if (mainColumn) mainColumn.classList.remove('with-whiteboard');
            if (whiteboardContainer) whiteboardContainer.classList.remove('active');
            broadcast({ type: 'whiteboard_toggle', state: false, senderId: state.currentRoom.localParticipant.identity });
        }
    });
}

const mobileWhiteboardCloseBtn = document.getElementById('mobileWhiteboardCloseBtn');
if (mobileWhiteboardCloseBtn) {
    mobileWhiteboardCloseBtn.addEventListener('click', () => {
        state.isWhiteboardActive = false;
        if (toggleWhiteboardBtn) toggleWhiteboardBtn.classList.remove('active');
        if (mainColumn) mainColumn.classList.remove('with-whiteboard');
        if (whiteboardContainer) whiteboardContainer.classList.remove('active');
    });
}

// Sidebars
export function closeAllSidebars() {
    [chatSidebar, peopleSidebar, pollQaSidebar].forEach(sidebar => {
        if(sidebar) {
            sidebar.classList.remove('active');
            sidebar.classList.remove('show');
            sidebar.classList.remove('open');
        }
    });
    const allButtons = [
        toggleChatBtn, togglePeopleBtn, togglePollsBtn,
        document.getElementById('toggleChatBtn'), document.getElementById('navChatBtn'),
        document.getElementById('togglePeopleBtn'), document.getElementById('navPeopleBtn'),
        document.getElementById('togglePollsBtn'), document.getElementById('navPollsBtn')
    ];
    allButtons.forEach(btn => {
        if(btn) btn.classList.remove('active');
    });
    const rightPanelContainer = document.querySelector('.right-panel-container');
    if(rightPanelContainer) rightPanelContainer.classList.remove('show');
}

export function toggleSidebar(sidebar, btn) {
    const rightPanelContainer = document.querySelector('.right-panel-container');
    if (!sidebar || !rightPanelContainer) return;
    const isCurrentlyActive = sidebar.classList.contains('active') || sidebar.classList.contains('show') || sidebar.classList.contains('open');
    closeAllSidebars();
    if (!isCurrentlyActive) {
        sidebar.classList.add('active');
        sidebar.classList.add('show');
        sidebar.classList.add('open');
        if(btn) btn.classList.add('active');
        rightPanelContainer.classList.add('show');
        if (sidebar === chatSidebar) {
            const badge = document.getElementById('chatBadge');
            if (badge) badge.style.display = 'none';
            const dockBadge = document.getElementById('dockChatBadge');
            if (dockBadge) dockBadge.style.display = 'none';
        }
        if (sidebar === pollQaSidebar) {
            const qaBadge = document.getElementById('qaBadge');
            if (qaBadge) qaBadge.style.display = 'none';
            state.newQaCount = 0;
            state.isPollQaOpen = true;
        }
    } else {
        if (sidebar === pollQaSidebar) state.isPollQaOpen = false;
    }
}

const chatToggleBtns = [document.getElementById('toggleChatBtn'), document.getElementById('navChatBtn')].filter(Boolean);
chatToggleBtns.forEach(btn => {
    btn.addEventListener('click', () => {
        toggleSidebar(chatSidebar, btn);
        chatToggleBtns.forEach(b => b.classList.toggle('active', chatSidebar.classList.contains('active')));
    });
});
const closeChatBtn = document.getElementById('closeChatBtn');
if (closeChatBtn) { closeChatBtn.addEventListener('click', closeAllSidebars); }

const peopleToggleBtns = [document.getElementById('togglePeopleBtn'), document.getElementById('navPeopleBtn')].filter(Boolean);
peopleToggleBtns.forEach(btn => {
    btn.addEventListener('click', () => {
        toggleSidebar(peopleSidebar, btn);
        peopleToggleBtns.forEach(b => b.classList.toggle('active', peopleSidebar.classList.contains('active')));
    });
});
const closePeopleBtn = document.getElementById('closePeopleBtn');
if (closePeopleBtn) { closePeopleBtn.addEventListener('click', closeAllSidebars); }

if (togglePollsBtn) {
    const closePollQaBtn = document.getElementById('closePollQaBtn');
    togglePollsBtn.addEventListener('click', () => { toggleSidebar(pollQaSidebar, togglePollsBtn); });
    if (closePollQaBtn) { closePollQaBtn.addEventListener('click', closeAllSidebars); }
}

if (navQaBtn) {
    navQaBtn.addEventListener('click', () => {
        toggleSidebar(pollQaSidebar, navQaBtn);
        const tabQA = document.getElementById('tabQA');
        if (tabQA) tabQA.click();
    });
}

// Leave Call Button
if (leaveCallBtn) {
    leaveCallBtn.addEventListener('click', () => {
        if (state.isAdmin) {
            const leaveModal = document.getElementById('leaveModal');
            if (leaveModal) leaveModal.style.display = 'flex';
        } else {
            leaveCall();
        }
    });
}

const closeLeaveModalBtn = document.getElementById('closeLeaveModalBtn');
const leaveMeetingOnlyBtn = document.getElementById('leaveMeetingOnlyBtn');
const endMeetingForAllBtn = document.getElementById('endMeetingForAllBtn');
if (closeLeaveModalBtn) closeLeaveModalBtn.addEventListener('click', () => document.getElementById('leaveModal').style.display = 'none');
if (leaveMeetingOnlyBtn) leaveMeetingOnlyBtn.addEventListener('click', () => {
    document.getElementById('leaveModal').style.display = 'none';
    leaveCall();
});
if (endMeetingForAllBtn) endMeetingForAllBtn.addEventListener('click', async () => {
    if (!state.currentRoom) return;
    try {
        const idToken = await getAuthToken();
        await fetch('/api/end_meeting', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${idToken}` },
            body: JSON.stringify({ room_id: state.currentRoom.name })
        });
        document.getElementById('leaveModal').style.display = 'none';
        leaveCall();
    } catch (e) {
        showToast("Failed to end meeting.", true);
    }
});

// ==========================================
// MORE DRAWER (Hick's Law categorised panel)
// ==========================================
const toggleMoreBtn = document.getElementById('toggleMoreBtn');
const moreDrawer = document.getElementById('moreDrawer');

function openMoreDrawer() {
    if (moreDrawer) moreDrawer.classList.add('open');
    if (toggleMoreBtn) toggleMoreBtn.classList.add('active');
}

function closeMoreDrawer() {
    if (moreDrawer) moreDrawer.classList.remove('open');
    if (toggleMoreBtn) toggleMoreBtn.classList.remove('active');
    if (emojiPopover) emojiPopover.style.display = 'none';
}

if (toggleMoreBtn) {
    toggleMoreBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        if (moreDrawer && moreDrawer.classList.contains('open')) {
            closeMoreDrawer();
        } else {
            openMoreDrawer();
        }
    });
}

// Close drawer on outside click
document.addEventListener('click', (e) => {
    if (!moreDrawer || !toggleMoreBtn) return;
    if (moreDrawer.classList.contains('open') &&
        !moreDrawer.contains(e.target) &&
        !toggleMoreBtn.contains(e.target)) {
        closeMoreDrawer();
    }
});

const closeDrawerBtn = document.getElementById('closeDrawerBtn');
if (closeDrawerBtn) {
    closeDrawerBtn.addEventListener('click', closeMoreDrawer);
}

// Wire drawer Interact nav items → panel toggles
const drawerChatBtn = document.getElementById('drawerChatBtn');
const drawerPeopleBtn = document.getElementById('drawerPeopleBtn');
const drawerWhiteboardBtn = document.getElementById('drawerWhiteboardBtn');
const drawerPollsBtn = document.getElementById('drawerPollsBtn');
const drawerQaBtn = document.getElementById('drawerQaBtn');

if (drawerChatBtn) drawerChatBtn.addEventListener('click', () => { closeMoreDrawer(); if (toggleChatBtn) toggleChatBtn.click(); });
if (drawerPeopleBtn) drawerPeopleBtn.addEventListener('click', () => { closeMoreDrawer(); if (togglePeopleBtn) togglePeopleBtn.click(); });
if (drawerWhiteboardBtn) drawerWhiteboardBtn.addEventListener('click', () => { closeMoreDrawer(); if (toggleWhiteboardBtn) toggleWhiteboardBtn.click(); });
if (drawerPollsBtn) drawerPollsBtn.addEventListener('click', () => { closeMoreDrawer(); if (togglePollsBtn) togglePollsBtn.click(); });
if (drawerQaBtn) drawerQaBtn.addEventListener('click', () => { closeMoreDrawer(); if (navQaBtn) navQaBtn.click(); });


const shareLinkBtn = document.getElementById('shareLinkBtn');
const toggleAppFullscreenBtn = document.getElementById('toggleAppFullscreenBtn');
const toggleSettingsMenuBtn = document.getElementById('toggleSettingsMenuBtn');

if (shareLinkBtn) {
    shareLinkBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        copyMeetingLink();
        closeMoreDrawer();
    });
}

if (toggleAppFullscreenBtn) {
    toggleAppFullscreenBtn.addEventListener('click', () => {
        toggleAppFullscreen();
        closeMoreDrawer();
    });
}

// Settings Modal
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

if (toggleSettingsMenuBtn && navSettingsBtn) {
    toggleSettingsMenuBtn.addEventListener('click', () => {
        closeMoreDrawer();
        navSettingsBtn.click();
    });
}

if (navSettingsBtn && settingsModal) {
    navSettingsBtn.addEventListener('click', async () => {
        await updateCameraDevicesList();
        await updateAudioDevicesList();
        populateSettingsDevices();
        settingsModal.style.display = 'flex';
    });
}

if (closeSettingsModalBtn && settingsModal) {
    closeSettingsModalBtn.addEventListener('click', () => {
        settingsModal.style.display = 'none';
    });
}

if (settingsAudioInputSelect) {
    settingsAudioInputSelect.addEventListener('change', async (e) => {
        if (e.target.value) await selectAudioInputDevice(e.target.value);
    });
}
if (settingsAudioOutputSelect) {
    settingsAudioOutputSelect.addEventListener('change', async (e) => {
        if (e.target.value) await selectAudioOutputDevice(e.target.value);
    });
}
if (settingsVideoInputSelect) {
    settingsVideoInputSelect.addEventListener('change', async (e) => {
        if (e.target.value) await selectCameraDevice(e.target.value);
    });
}

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
if (settingsCopyLinkBtn) {
    settingsCopyLinkBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        copyMeetingLink();
    });
}

// Data Saver Toggles
const toggleDataSaverBtn = document.getElementById('toggleDataSaverBtn');
if (toggleDataSaverBtn) {
    toggleDataSaverBtn.addEventListener('click', () => {
        closeMoreDrawer();
        toggleDataSaverMode();
    });
}
if (settingsDataSaverToggleBtn) {
    settingsDataSaverToggleBtn.addEventListener('click', () => {
        toggleDataSaverMode();
    });
}

// Live Captions Toggles
const toggleCaptionsBtn = document.getElementById('toggleCaptionsBtn');
const toggleCaptionsDrawerBtn = document.getElementById('toggleCaptionsDrawerBtn');
const settingsCaptionsToggleBtn = document.getElementById('settingsCaptionsToggleBtn');

if (toggleCaptionsBtn) {
    toggleCaptionsBtn.addEventListener('click', () => {
        toggleCaptions();
    });
}
if (toggleCaptionsDrawerBtn) {
    toggleCaptionsDrawerBtn.addEventListener('click', () => {
        closeMoreDrawer();
        toggleCaptions();
    });
}
if (settingsCaptionsToggleBtn) {
    settingsCaptionsToggleBtn.addEventListener('click', () => {
        toggleCaptions();
    });
}

// vMix Ingest Modal
const toggleVmixBtn = document.getElementById('toggleVmixBtn');
const vmixModal = document.getElementById('vmixModal');
const closeVmixModalBtn = document.getElementById('closeVmixModalBtn');
const copyVmixUrlBtn = document.getElementById('copyVmixUrlBtn');
const copyVmixKeyBtn = document.getElementById('copyVmixKeyBtn');

if (toggleVmixBtn && vmixModal) {
    toggleVmixBtn.addEventListener('click', async () => {
        if (!state.currentRoom) return;
        vmixModal.style.display = 'flex';
        closeMoreDrawer();

        const rtmpInput = document.getElementById('vmixRtmpUrl');
        const keyInput = document.getElementById('vmixStreamKey');
        if (rtmpInput) rtmpInput.value = 'Fetching credentials...';
        if (keyInput) keyInput.value = 'Fetching credentials...';

        try {
            const idToken = await getAuthToken();
            const headers = { 'Content-Type': 'application/json' };
            if (idToken) headers['Authorization'] = `Bearer ${idToken}`;

            const res = await fetch('/api/create_ingress', {
                method: 'POST',
                headers: headers,
                body: JSON.stringify({ room_id: state.currentRoom.name })
            });
            const data = await res.json();
            if (res.ok && data.status === 'success') {
                if (rtmpInput) rtmpInput.value = data.rtmp_url;
                if (keyInput) keyInput.value = data.stream_key;
                showToast("vMix RTMP credentials ready!");
            } else {
                const errMsg = data.detail || "Failed to fetch vMix credentials.";
                if (rtmpInput) rtmpInput.value = errMsg;
                if (keyInput) keyInput.value = 'Unavailable';
                showToast(errMsg, true);
            }
        } catch (e) {
            console.error("Error fetching vMix credentials:", e);
            if (rtmpInput) rtmpInput.value = 'Connection failed';
            if (keyInput) keyInput.value = 'Connection failed';
            showToast("Failed to connect to vMix Ingress service.", true);
        }
    });
}

if (closeVmixModalBtn && vmixModal) {
    closeVmixModalBtn.addEventListener('click', () => { vmixModal.style.display = 'none'; });
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

// Multi-Streaming Modal
const toggleMultiStreamBtn = document.getElementById('toggleMultiStreamBtn');
const multiStreamModal = document.getElementById('multiStreamModal');
const closeMultiStreamModalBtn = document.getElementById('closeMultiStreamModalBtn');
if (toggleMultiStreamBtn && multiStreamModal) {
    toggleMultiStreamBtn.addEventListener('click', () => {
        closeMoreDrawer();
        multiStreamModal.style.display = 'flex';
    });
}
if (closeMultiStreamModalBtn && multiStreamModal) {
    closeMultiStreamModalBtn.addEventListener('click', () => { multiStreamModal.style.display = 'none'; });
}

// User Support Modal
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
        if (userSupportAlert) userSupportAlert.style.display = 'none';
        supportModal.style.display = 'flex';
    });
    if (closeSupportModalBtn) closeSupportModalBtn.addEventListener('click', () => { supportModal.style.display = 'none'; });
    supportModal.addEventListener('click', (e) => {
        if (e.target === supportModal) supportModal.style.display = 'none';
    });

    if (userSupportForm) {
        userSupportForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            if (userSupportSubmitBtn) {
                userSupportSubmitBtn.disabled = true;
                userSupportSubmitBtn.innerHTML = `<span class="material-symbols-outlined spin-icon">sync</span> Submitting...`;
            }
            try {
                const token = await getAuthToken();
                if (!token) {
                    if (userSupportAlert) {
                        userSupportAlert.textContent = 'Please log in or create a free account to submit a support ticket.';
                        userSupportAlert.style.display = 'block';
                    }
                    return;
                }
                const res = await fetch('/api/support/tickets', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
                    body: JSON.stringify({
                        category: userSupportCategory.value,
                        subject: userSupportSubject.value.trim(),
                        message: userSupportMessage.value.trim()
                    })
                });
                const data = await res.json();
                if (!res.ok) throw new Error(data.detail || 'Failed to submit ticket');

                if (userSupportAlert) {
                    userSupportAlert.innerHTML = `🎉 <strong>Ticket #${data.ticket_id} Created!</strong> Our team will review shortly.`;
                    userSupportAlert.style.display = 'block';
                }
                userSupportSubject.value = '';
                userSupportMessage.value = '';
                setTimeout(() => { supportModal.style.display = 'none'; }, 3500);
            } catch (err) {
                if (userSupportAlert) {
                    userSupportAlert.textContent = `Error: ${err.message}`;
                    userSupportAlert.style.display = 'block';
                }
            } finally {
                if (userSupportSubmitBtn) {
                    userSupportSubmitBtn.disabled = false;
                    userSupportSubmitBtn.innerHTML = `<span class="material-symbols-outlined">send</span> Submit Support Ticket`;
                }
            }
        });
    }
}

// ==========================================
// SIDEBAR COLLAPSE / EXPAND LOGIC (Hick's Law)
// ==========================================
const leftSidebar = document.getElementById('leftSidebar');
const sidebarBrand = document.querySelector('.sidebar-brand');
const collapseSidebarBtn = document.getElementById('collapseSidebarBtn');
const collapseIcon = document.getElementById('collapseIcon');

function toggleSidebarExpand() {
    if (!leftSidebar) return;
    const isExpanded = leftSidebar.classList.toggle('expanded');
    if (collapseIcon) {
        collapseIcon.textContent = isExpanded ? 'keyboard_double_arrow_left' : 'keyboard_double_arrow_right';
    }
}

if (sidebarBrand) {
    sidebarBrand.style.cursor = 'pointer';
    sidebarBrand.addEventListener('click', toggleSidebarExpand);
}

if (collapseSidebarBtn) {
    collapseSidebarBtn.addEventListener('click', toggleSidebarExpand);
}

// ==========================================
// MOBILE BOTTOM SHEET LOGIC (Hick's Law)
// ==========================================
const mobileMenuBtn = document.getElementById('mobileMenuBtn');
const mobilePanelSheet = document.getElementById('mobilePanelSheet');
const sheetBackdrop = document.getElementById('sheetBackdrop');
const mobileEmojiPopover = document.getElementById('mobileEmojiPopover');

function openMobileSheet() {
    if (mobilePanelSheet) mobilePanelSheet.classList.add('open');
    if (sheetBackdrop) sheetBackdrop.classList.add('visible');
}

function closeMobileSheet() {
    if (mobilePanelSheet) mobilePanelSheet.classList.remove('open');
    if (sheetBackdrop) sheetBackdrop.classList.remove('visible');
    if (mobileEmojiPopover) mobileEmojiPopover.style.display = 'none';
}

// Expose globally for module / external access
window.closeMobileSheet = closeMobileSheet;
window.openMobileSheet = openMobileSheet;

if (mobileMenuBtn) {
    mobileMenuBtn.addEventListener('click', openMobileSheet);
}
if (sheetBackdrop) {
    sheetBackdrop.addEventListener('click', closeMobileSheet);
}

// Swipe down or click handle to close mobile sheet
const sheetHandle = document.querySelector('.mobile-sheet-handle');
if (sheetHandle) {
    sheetHandle.addEventListener('click', closeMobileSheet);
}

// Wire mobile sheet buttons to their corresponding desktop counterparts
const mobileSheetProxyMap = [
    ['mobileSheetPeopleBtn', () => { if (togglePeopleBtn) togglePeopleBtn.click(); }],
    ['mobileSheetChatBtn', () => { if (toggleChatBtn) toggleChatBtn.click(); }],
    ['mobileSheetWhiteboardBtn', () => { if (toggleWhiteboardBtn) toggleWhiteboardBtn.click(); }],
    ['mobileSheetPollsBtn', () => { if (togglePollsBtn) togglePollsBtn.click(); }],
    ['mobileSheetQaBtn', () => { if (navQaBtn) navQaBtn.click(); }],
    ['mobileSheetHandBtn', () => { if (toggleHandBtn) toggleHandBtn.click(); }],
    ['mobileSheetEffectsBtn', () => { if (toggleEffectsBtn) toggleEffectsBtn.click(); }],
    ['mobileSheetNoiseBtn', () => { if (toggleNoiseBtn) toggleNoiseBtn.click(); }],
    ['mobileSheetShareBtn', () => { if (shareLinkBtn) shareLinkBtn.click(); }],
    ['mobileSheetSettingsBtn', () => { if (navSettingsBtn) navSettingsBtn.click(); }],
    ['mobileSheetDataSaverBtn', () => { toggleDataSaverMode(); }],
    ['mobileSheetCaptionsBtn', () => { toggleCaptions(); }],
];

mobileSheetProxyMap.forEach(([btnId, actionFn]) => {
    const btn = document.getElementById(btnId);
    if (btn) {
        btn.addEventListener('click', () => {
            closeMobileSheet();
            actionFn();
        });
    }
});

// Mobile sheet react button toggle
const mobileSheetReactBtn = document.getElementById('mobileSheetReactBtn');
if (mobileSheetReactBtn) {
    mobileSheetReactBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        if (mobileEmojiPopover) {
            const isShowing = mobileEmojiPopover.style.display === 'flex';
            mobileEmojiPopover.style.display = isShowing ? 'none' : 'flex';
        }
    });
}

// Sync chat badges across bottom dock, desktop drawer, and mobile sheet
const chatBadge = document.getElementById('chatBadge');
const drawerChatBadge = document.getElementById('drawerChatBadge');
const mobileSheetChatBadge = document.getElementById('mobileSheetChatBadge');
const dockChatBadge = document.getElementById('dockChatBadge');

if (chatBadge) {
    const syncBadges = () => {
        const isVisible = chatBadge.style.display !== 'none' && chatBadge.style.display !== '';
        if (drawerChatBadge) drawerChatBadge.style.display = isVisible ? 'block' : 'none';
        if (mobileSheetChatBadge) mobileSheetChatBadge.style.display = isVisible ? 'block' : 'none';
        if (dockChatBadge) {
            dockChatBadge.style.display = isVisible ? 'flex' : 'none';
            dockChatBadge.textContent = chatBadge.textContent || '1';
        }
    };
    const badgeObserver = new MutationObserver(syncBadges);
    badgeObserver.observe(chatBadge, { attributes: true, characterData: true, childList: true, attributeFilter: ['style', 'class'] });
}

