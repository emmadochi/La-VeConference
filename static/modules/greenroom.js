// ==========================================
// PRE-CALL GREEN ROOM / DEVICE CHECK
// ==========================================
import { state } from "./state.js";
import { showToast } from "./utils.js";

let greenRoomStream = null;
let audioContext = null;
let analyser = null;
let rafId = null;

let isMicActive = true;
let isVideoActive = true;
let currentCameraId = null;
let currentMicId = null;

export async function openGreenRoom(roomId, userName, onJoin, onCancel, isHost = false) {
    const overlay = document.getElementById('greenRoomOverlay');
    if (!overlay) {
        console.warn("greenRoomOverlay element not found, falling back to direct join");
        if (typeof onJoin === 'function') onJoin();
        return;
    }

    // Reset local green room state
    isMicActive = true;
    isVideoActive = true;
    currentCameraId = state.activeCameraDeviceId || localStorage.getItem('preferred_camera_id') || null;
    currentMicId = state.activeAudioInputDeviceId || localStorage.getItem('preferred_mic_id') || null;

    overlay.style.display = 'flex';

    // Update room title and user badge
    const titleEl = document.getElementById('greenRoomRoomId');
    if (titleEl) titleEl.textContent = roomId;
    const nameEl = document.getElementById('greenRoomUserName');
    if (nameEl) nameEl.textContent = userName;

    // Update modal title and CTA button based on host/participant role
    const headerTitle = document.getElementById('greenRoomTitle');
    const joinBtnText = document.getElementById('greenRoomJoinBtnText');
    const joinBtnIcon = document.getElementById('greenRoomJoinBtnIcon');

    if (isHost) {
        if (headerTitle) headerTitle.textContent = "Ready to start?";
        if (joinBtnText) joinBtnText.textContent = "Create Now";
        if (joinBtnIcon) joinBtnIcon.textContent = "video_call";
    } else {
        if (headerTitle) headerTitle.textContent = "Ready to join?";
        if (joinBtnText) joinBtnText.textContent = "Join Now";
        if (joinBtnIcon) joinBtnIcon.textContent = "login";
    }

    // Start local preview stream
    await startGreenRoomPreview();

    // Populate device selectors
    await populateGreenRoomDevices();

    // Bind controls
    bindGreenRoomControls(roomId, userName, onJoin, onCancel);
}

async function startGreenRoomPreview() {
    stopGreenRoomStream();

    const videoEl = document.getElementById('greenRoomVideo');
    const placeholderEl = document.getElementById('greenRoomVideoPlaceholder');

    try {
        const constraints = {
            video: currentCameraId ? { deviceId: { exact: currentCameraId } } : true,
            audio: currentMicId ? { deviceId: { exact: currentMicId } } : true
        };

        greenRoomStream = await navigator.mediaDevices.getUserMedia(constraints);

        if (videoEl) {
            videoEl.srcObject = greenRoomStream;
            videoEl.style.display = isVideoActive ? 'block' : 'none';
            if (placeholderEl) placeholderEl.style.display = isVideoActive ? 'none' : 'flex';
        }

        // Setup audio meter canvas
        setupAudioMeter(greenRoomStream);

        // Track active devices from stream settings
        const videoTrack = greenRoomStream.getVideoTracks()[0];
        if (videoTrack && videoTrack.getSettings) {
            const settings = videoTrack.getSettings();
            if (settings.deviceId) currentCameraId = settings.deviceId;
        }

        const audioTrack = greenRoomStream.getAudioTracks()[0];
        if (audioTrack && audioTrack.getSettings) {
            const settings = audioTrack.getSettings();
            if (settings.deviceId) currentMicId = settings.deviceId;
        }

        updateControlsUI();
    } catch (err) {
        console.warn("Green room camera/mic preview permission or device error:", err);
        // Fallback: audio only or listen-only preview
        try {
            greenRoomStream = await navigator.mediaDevices.getUserMedia({ audio: true, video: false });
            if (videoEl) videoEl.style.display = 'none';
            if (placeholderEl) placeholderEl.style.display = 'flex';
            setupAudioMeter(greenRoomStream);
            isVideoActive = false;
            updateControlsUI();
        } catch (audioErr) {
            console.warn("No mic or camera access for preview:", audioErr);
            if (videoEl) videoEl.style.display = 'none';
            if (placeholderEl) placeholderEl.style.display = 'flex';
            isMicActive = false;
            isVideoActive = false;
            updateControlsUI();
        }
    }
}

function setupAudioMeter(stream) {
    const audioTrack = stream.getAudioTracks()[0];
    if (!audioTrack) return;

    try {
        audioContext = new (window.AudioContext || window.webkitAudioContext)();
        const source = audioContext.createMediaStreamSource(new MediaStream([audioTrack]));
        analyser = audioContext.createAnalyser();
        analyser.fftSize = 64;
        source.connect(analyser);

        const canvas = document.getElementById('greenRoomAudioMeter');
        if (!canvas) return;
        const ctx = canvas.getContext('2d');
        const bufferLength = analyser.frequencyBinCount;
        const dataArray = new Uint8Array(bufferLength);

        function drawMeter() {
            if (!analyser || !audioContext) return;
            rafId = requestAnimationFrame(drawMeter);

            analyser.getByteFrequencyData(dataArray);

            let sum = 0;
            for (let i = 0; i < bufferLength; i++) {
                sum += dataArray[i];
            }
            const average = isMicActive ? (sum / bufferLength) : 0;
            const normalized = Math.min(1, average / 80); // 0 to 1 scale

            ctx.clearRect(0, 0, canvas.width, canvas.height);

            // Draw level bar
            const totalBars = 12;
            const barWidth = (canvas.width - (totalBars - 1) * 3) / totalBars;
            const activeBars = Math.round(normalized * totalBars);

            for (let i = 0; i < totalBars; i++) {
                const x = i * (barWidth + 3);
                const isLit = i < activeBars;
                
                // Color gradient from green to cyan to yellow
                if (isLit) {
                    if (i < 8) ctx.fillStyle = '#00e5ff';
                    else if (i < 10) ctx.fillStyle = '#10b981';
                    else ctx.fillStyle = '#f59e0b';
                } else {
                    ctx.fillStyle = 'rgba(255, 255, 255, 0.15)';
                }

                ctx.beginPath();
                ctx.roundRect(x, 2, barWidth, canvas.height - 4, 2);
                ctx.fill();
            }
        }

        drawMeter();
    } catch (e) {
        console.warn("Audio meter setup error:", e);
    }
}

async function populateGreenRoomDevices() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) return;
    try {
        const devices = await navigator.mediaDevices.enumerateDevices();
        const videoDevices = devices.filter(d => d.kind === 'videoinput');
        const audioDevices = devices.filter(d => d.kind === 'audioinput');

        const camSelect = document.getElementById('greenRoomCamSelect');
        if (camSelect) {
            camSelect.innerHTML = '';
            if (videoDevices.length > 0) {
                videoDevices.forEach((d, i) => {
                    const opt = document.createElement('option');
                    opt.value = d.deviceId;
                    opt.textContent = d.label || `Camera ${i + 1}`;
                    if (d.deviceId === currentCameraId) opt.selected = true;
                    camSelect.appendChild(opt);
                });
            } else {
                const opt = document.createElement('option');
                opt.value = '';
                opt.textContent = 'No camera found';
                camSelect.appendChild(opt);
            }
        }

        const micSelect = document.getElementById('greenRoomMicSelect');
        if (micSelect) {
            micSelect.innerHTML = '';
            if (audioDevices.length > 0) {
                audioDevices.forEach((d, i) => {
                    const opt = document.createElement('option');
                    opt.value = d.deviceId;
                    opt.textContent = d.label || `Microphone ${i + 1}`;
                    if (d.deviceId === currentMicId) opt.selected = true;
                    micSelect.appendChild(opt);
                });
            } else {
                const opt = document.createElement('option');
                opt.value = '';
                opt.textContent = 'No microphone found';
                micSelect.appendChild(opt);
            }
        }
    } catch (e) {
        console.warn("Error enumerating devices in green room:", e);
    }
}

function updateControlsUI() {
    const toggleMicBtn = document.getElementById('greenRoomToggleMic');
    const toggleCamBtn = document.getElementById('greenRoomToggleCam');
    const videoEl = document.getElementById('greenRoomVideo');
    const placeholderEl = document.getElementById('greenRoomVideoPlaceholder');

    if (toggleMicBtn) {
        toggleMicBtn.classList.toggle('off', !isMicActive);
        const icon = toggleMicBtn.querySelector('.material-symbols-outlined');
        if (icon) icon.textContent = isMicActive ? 'mic' : 'mic_off';
    }

    if (toggleCamBtn) {
        toggleCamBtn.classList.toggle('off', !isVideoActive);
        const icon = toggleCamBtn.querySelector('.material-symbols-outlined');
        if (icon) icon.textContent = isVideoActive ? 'videocam' : 'videocam_off';
    }

    if (videoEl) {
        videoEl.style.display = isVideoActive ? 'block' : 'none';
    }
    if (placeholderEl) {
        placeholderEl.style.display = isVideoActive ? 'none' : 'flex';
    }
}

function bindGreenRoomControls(roomId, userName, onJoin, onCancel) {
    const toggleMicBtn = document.getElementById('greenRoomToggleMic');
    const toggleCamBtn = document.getElementById('greenRoomToggleCam');
    const camSelect = document.getElementById('greenRoomCamSelect');
    const micSelect = document.getElementById('greenRoomMicSelect');
    const joinBtn = document.getElementById('greenRoomJoinBtn');
    const cancelBtn = document.getElementById('greenRoomCancelBtn');
    const closeBtn = document.getElementById('greenRoomCloseBtn');

    if (toggleMicBtn) {
        toggleMicBtn.onclick = () => {
            isMicActive = !isMicActive;
            if (greenRoomStream) {
                greenRoomStream.getAudioTracks().forEach(t => t.enabled = isMicActive);
            }
            updateControlsUI();
        };
    }

    if (toggleCamBtn) {
        toggleCamBtn.onclick = () => {
            isVideoActive = !isVideoActive;
            if (greenRoomStream) {
                greenRoomStream.getVideoTracks().forEach(t => t.enabled = isVideoActive);
            }
            updateControlsUI();
        };
    }

    if (camSelect) {
        camSelect.onchange = async () => {
            currentCameraId = camSelect.value;
            state.activeCameraDeviceId = currentCameraId;
            try { localStorage.setItem('preferred_camera_id', currentCameraId); } catch(e) {}
            await startGreenRoomPreview();
        };
    }

    if (micSelect) {
        micSelect.onchange = async () => {
            currentMicId = micSelect.value;
            state.activeAudioInputDeviceId = currentMicId;
            try { localStorage.setItem('preferred_mic_id', currentMicId); } catch(e) {}
            await startGreenRoomPreview();
        };
    }

    const dismissAndExit = () => {
        closeGreenRoom();
        if (typeof onCancel === 'function') onCancel();
    };

    if (cancelBtn) cancelBtn.onclick = dismissAndExit;
    if (closeBtn) closeBtn.onclick = dismissAndExit;

    if (joinBtn) {
        joinBtn.onclick = () => {
            // Save preferences
            state.greenRoomSettings = {
                cameraDeviceId: currentCameraId,
                audioDeviceId: currentMicId,
                isMicEnabled: isMicActive,
                isVideoEnabled: isVideoActive
            };
            state.isMicEnabled = isMicActive;
            state.isVideoEnabled = isVideoActive;
            if (currentCameraId) state.activeCameraDeviceId = currentCameraId;
            if (currentMicId) state.activeAudioInputDeviceId = currentMicId;

            closeGreenRoom();

            if (typeof onJoin === 'function') {
                onJoin(state.greenRoomSettings);
            }
        };
    }
}

export function closeGreenRoom() {
    stopGreenRoomStream();
    const overlay = document.getElementById('greenRoomOverlay');
    if (overlay) overlay.style.display = 'none';
}

function stopGreenRoomStream() {
    if (rafId) {
        cancelAnimationFrame(rafId);
        rafId = null;
    }
    if (analyser) {
        try { analyser.disconnect(); } catch(e) {}
        analyser = null;
    }
    if (audioContext) {
        try { audioContext.close(); } catch(e) {}
        audioContext = null;
    }
    if (greenRoomStream) {
        // Critical: Stop all hardware tracks so camera LED goes OFF!
        greenRoomStream.getTracks().forEach(track => {
            try { track.stop(); } catch (e) {}
        });
        greenRoomStream = null;
    }
    const videoEl = document.getElementById('greenRoomVideo');
    if (videoEl) videoEl.srcObject = null;
}
