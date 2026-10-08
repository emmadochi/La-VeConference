// ==========================================
// MEDIA DEVICE MANAGEMENT & SELECTION
// ==========================================
import { state } from "./state.js";
import { showToast } from "./utils.js";
import * as LivekitClient from "https://esm.sh/livekit-client@2.20.1";

const { Track } = LivekitClient;

export async function updateCameraDevicesList() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) return;
    try {
        const devices = await navigator.mediaDevices.enumerateDevices();
        state.availableVideoDevices = devices.filter(d => d.kind === 'videoinput');
        
        const isCurrentDeviceStillAvailable = state.availableVideoDevices.some(d => d.deviceId === state.activeCameraDeviceId);
        
        if (!isCurrentDeviceStillAvailable) {
            if (state.currentRoom && state.currentRoom.localParticipant) {
                const pub = state.currentRoom.localParticipant.getTrackPublication(Track.Source.Camera);
                const mediaStreamTrack = pub?.videoTrack?.mediaStreamTrack;
                if (mediaStreamTrack && typeof mediaStreamTrack.getSettings === 'function') {
                    const settings = mediaStreamTrack.getSettings();
                    if (settings && settings.deviceId) {
                        state.activeCameraDeviceId = settings.deviceId;
                    }
                }
            }
            if (!state.activeCameraDeviceId && state.availableVideoDevices.length > 0) {
                const savedPref = localStorage.getItem('preferred_camera_id');
                const matchedPref = savedPref && state.availableVideoDevices.find(d => d.deviceId === savedPref);
                state.activeCameraDeviceId = matchedPref ? matchedPref.deviceId : state.availableVideoDevices[0].deviceId;
            }
        }

        const flipCameraBtn = document.getElementById('flipCameraBtn');
        const flipCameraBtnText = document.getElementById('flipCameraBtnText');
        const cameraListContainer = document.getElementById('cameraListContainer');

        if (flipCameraBtn) {
            if (state.availableVideoDevices.length > 0) {
                flipCameraBtn.style.display = 'flex';
                if (flipCameraBtnText) {
                    flipCameraBtnText.textContent = state.availableVideoDevices.length > 1 ? 'Switch Camera' : 'Camera Options';
                }
            } else {
                flipCameraBtn.style.display = 'none';
            }
        }

        if (cameraListContainer) {
            const wasOpen = cameraListContainer.style.display === 'flex';
            if (state.availableVideoDevices.length > 0) {
                cameraListContainer.innerHTML = '';
                state.availableVideoDevices.forEach((device, idx) => {
                    const label = device.label || `Camera ${idx + 1}`;
                    const isCurrent = device.deviceId === state.activeCameraDeviceId;
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

export async function selectCameraDevice(targetDeviceId) {
    state.activeCameraDeviceId = targetDeviceId;
    try { localStorage.setItem('preferred_camera_id', targetDeviceId); } catch(e) {}

    if (!state.currentRoom) return;

    try {
        let switchSucceeded = false;
        if (typeof state.currentRoom.switchActiveDevice === 'function') {
            try {
                await state.currentRoom.switchActiveDevice('videoinput', targetDeviceId);
                switchSucceeded = true;
            } catch (swErr) {
                console.warn("switchActiveDevice failed, falling back to camera toggle:", swErr);
            }
        }
        
        if (!switchSucceeded && state.currentRoom.localParticipant) {
            await state.currentRoom.localParticipant.setCameraEnabled(false);
            await new Promise(r => setTimeout(r, 250));
            await state.currentRoom.localParticipant.setCameraEnabled(true, {
                deviceId: targetDeviceId
            });
        }

        const pub = state.currentRoom.localParticipant.getTrackPublication(Track.Source.Camera);
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

        if (state.backgroundProcessor) {
            try {
                const videoTrack = state.currentRoom.localParticipant.getTrackPublication(Track.Source.Camera)?.videoTrack;
                if (videoTrack) {
                    await videoTrack.setProcessor(state.backgroundProcessor);
                }
            } catch (procErr) {
                console.warn("Background processor skipped for device:", procErr);
            }
        }

        await updateCameraDevicesList();

        const selectedDevice = state.availableVideoDevices.find(d => d.deviceId === targetDeviceId);
        const label = selectedDevice ? (selectedDevice.label || 'Camera') : 'Camera';
        showToast(`Switched camera to: ${label}`);
    } catch (err) {
        console.error("Error switching camera device:", err);
        showToast("Could not switch camera: " + (err.message || "Unknown error"), true);
    }
}

export async function updateAudioDevicesList() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) return;
    try {
        const devices = await navigator.mediaDevices.enumerateDevices();
        state.availableAudioInputDevices = devices.filter(d => d.kind === 'audioinput');
        state.availableAudioOutputDevices = devices.filter(d => d.kind === 'audiooutput');

        const isCurrentMicStillAvailable = state.availableAudioInputDevices.some(d => d.deviceId === state.activeAudioInputDeviceId);
        if (!isCurrentMicStillAvailable) {
            if (state.currentRoom && state.currentRoom.localParticipant) {
                const pub = state.currentRoom.localParticipant.getTrackPublication(Track.Source.Microphone);
                const mediaStreamTrack = pub?.audioTrack?.mediaStreamTrack;
                if (mediaStreamTrack && typeof mediaStreamTrack.getSettings === 'function') {
                    const settings = mediaStreamTrack.getSettings();
                    if (settings && settings.deviceId) {
                        state.activeAudioInputDeviceId = settings.deviceId;
                    }
                }
            }
            if (!state.activeAudioInputDeviceId && state.availableAudioInputDevices.length > 0) {
                const savedPref = localStorage.getItem('preferred_mic_id');
                const matchedPref = savedPref && state.availableAudioInputDevices.find(d => d.deviceId === savedPref);
                state.activeAudioInputDeviceId = matchedPref ? matchedPref.deviceId : state.availableAudioInputDevices[0].deviceId;
            }
        }

        const audioDevicesBtn = document.getElementById('audioDevicesBtn');
        const audioListContainer = document.getElementById('audioListContainer');
        const speakerDevicesBtn = document.getElementById('speakerDevicesBtn');
        const speakerListContainer = document.getElementById('speakerListContainer');

        if (audioDevicesBtn) {
            audioDevicesBtn.style.display = state.availableAudioInputDevices.length > 0 ? 'flex' : 'none';
        }

        if (audioListContainer) {
            const wasOpen = audioListContainer.style.display === 'flex';
            if (state.availableAudioInputDevices.length > 0) {
                audioListContainer.innerHTML = '';
                state.availableAudioInputDevices.forEach((device, idx) => {
                    const label = device.label || `Microphone ${idx + 1}`;
                    const isCurrent = device.deviceId === state.activeAudioInputDeviceId;
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

        if (speakerDevicesBtn && speakerListContainer) {
            const wasOpen = speakerListContainer.style.display === 'flex';
            if (state.availableAudioOutputDevices.length > 0 && 'setSinkId' in HTMLMediaElement.prototype) {
                speakerDevicesBtn.style.display = 'flex';
                speakerListContainer.innerHTML = '';
                state.availableAudioOutputDevices.forEach((device, idx) => {
                    const label = device.label || `Speaker ${idx + 1}`;
                    const isCurrent = device.deviceId === state.activeAudioOutputDeviceId;
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

export async function selectAudioInputDevice(targetDeviceId) {
    state.activeAudioInputDeviceId = targetDeviceId;
    try { localStorage.setItem('preferred_mic_id', targetDeviceId); } catch(e) {}

    if (!state.currentRoom) return;

    try {
        let switchSucceeded = false;
        if (typeof state.currentRoom.switchActiveDevice === 'function') {
            try {
                await state.currentRoom.switchActiveDevice('audioinput', targetDeviceId);
                switchSucceeded = true;
            } catch (swErr) {
                console.warn("switchActiveDevice audioinput failed, falling back to mic toggle:", swErr);
            }
        }

        if (!switchSucceeded && state.currentRoom.localParticipant) {
            const wasEnabled = state.isMicEnabled;
            await state.currentRoom.localParticipant.setMicrophoneEnabled(false);
            if (wasEnabled) {
                await new Promise(r => setTimeout(r, 200));
                await state.currentRoom.localParticipant.setMicrophoneEnabled(true, {
                    deviceId: targetDeviceId
                }, { dtx: true });
            }
        }

        await updateAudioDevicesList();

        const selectedDevice = state.availableAudioInputDevices.find(d => d.deviceId === targetDeviceId);
        const label = selectedDevice ? (selectedDevice.label || 'Microphone') : 'Microphone';
        showToast(`Switched microphone to: ${label}`);
    } catch (err) {
        console.error("Error switching audio input:", err);
        showToast("Could not switch microphone: " + (err.message || "Unknown error"), true);
    }
}

export async function selectAudioOutputDevice(targetDeviceId) {
    state.activeAudioOutputDeviceId = targetDeviceId;
    try { localStorage.setItem('preferred_speaker_id', targetDeviceId); } catch(e) {}

    if (!state.currentRoom) return;

    try {
        if (typeof state.currentRoom.switchActiveDevice === 'function') {
            await state.currentRoom.switchActiveDevice('audiooutput', targetDeviceId);
        }

        document.querySelectorAll('audio, video').forEach(el => {
            if (typeof el.setSinkId === 'function') {
                el.setSinkId(targetDeviceId).catch(e => console.warn("Failed setSinkId on element:", e));
            }
        });

        await updateAudioDevicesList();

        const selectedDevice = state.availableAudioOutputDevices.find(d => d.deviceId === targetDeviceId);
        const label = selectedDevice ? (selectedDevice.label || 'Speaker') : 'Speaker';
        showToast(`Switched speaker to: ${label}`);
    } catch (err) {
        console.error("Error switching audio output:", err);
        showToast("Could not switch speaker: " + (err.message || "Unknown error"), true);
    }
}

export function populateSettingsDevices() {
    const settingsAudioInputSelect = document.getElementById('settingsAudioInputSelect');
    const settingsAudioOutputSelect = document.getElementById('settingsAudioOutputSelect');
    const settingsVideoInputSelect = document.getElementById('settingsVideoInputSelect');
    const settingsNoiseToggleBtn = document.getElementById('settingsNoiseToggleBtn');
    const settingsDataSaverToggleBtn = document.getElementById('settingsDataSaverToggleBtn');

    if (settingsAudioInputSelect) {
        settingsAudioInputSelect.innerHTML = '';
        if (state.availableAudioInputDevices.length > 0) {
            state.availableAudioInputDevices.forEach((device, idx) => {
                const opt = document.createElement('option');
                opt.value = device.deviceId;
                opt.textContent = device.label || `Microphone ${idx + 1}`;
                if (device.deviceId === state.activeAudioInputDeviceId) opt.selected = true;
                settingsAudioInputSelect.appendChild(opt);
            });
        } else {
            const opt = document.createElement('option');
            opt.value = '';
            opt.textContent = 'Default Microphone';
            settingsAudioInputSelect.appendChild(opt);
        }
    }

    if (settingsAudioOutputSelect) {
        settingsAudioOutputSelect.innerHTML = '';
        if (state.availableAudioOutputDevices.length > 0 && 'setSinkId' in HTMLMediaElement.prototype) {
            state.availableAudioOutputDevices.forEach((device, idx) => {
                const opt = document.createElement('option');
                opt.value = device.deviceId;
                opt.textContent = device.label || `Speaker ${idx + 1}`;
                if (device.deviceId === state.activeAudioOutputDeviceId) opt.selected = true;
                settingsAudioOutputSelect.appendChild(opt);
            });
        } else {
            const opt = document.createElement('option');
            opt.value = '';
            opt.textContent = 'System Default Output';
            settingsAudioOutputSelect.appendChild(opt);
        }
    }

    if (settingsVideoInputSelect) {
        settingsVideoInputSelect.innerHTML = '';
        if (state.availableVideoDevices.length > 0) {
            state.availableVideoDevices.forEach((device, idx) => {
                const opt = document.createElement('option');
                opt.value = device.deviceId;
                opt.textContent = device.label || `Camera ${idx + 1}`;
                if (device.deviceId === state.activeCameraDeviceId) opt.selected = true;
                settingsVideoInputSelect.appendChild(opt);
            });
        } else {
            const opt = document.createElement('option');
            opt.value = '';
            opt.textContent = 'Default Camera';
            settingsVideoInputSelect.appendChild(opt);
        }
    }

    if (settingsNoiseToggleBtn) {
        settingsNoiseToggleBtn.textContent = state.isNoiseCancellationEnabled ? 'Enabled' : 'Disabled';
        settingsNoiseToggleBtn.style.color = state.isNoiseCancellationEnabled ? '#10b981' : 'white';
    }
    if (settingsDataSaverToggleBtn) {
        const isDataSaver = document.body.classList.contains('data-saver-active');
        settingsDataSaverToggleBtn.textContent = isDataSaver ? 'Enabled' : 'Disabled';
        settingsDataSaverToggleBtn.style.color = isDataSaver ? '#10b981' : 'white';
    }
}

export function initDeviceListeners() {
    let _deviceChangeTimer = null;
    if (navigator.mediaDevices && navigator.mediaDevices.addEventListener) {
        navigator.mediaDevices.addEventListener('devicechange', () => {
            if (_deviceChangeTimer) clearTimeout(_deviceChangeTimer);
            _deviceChangeTimer = setTimeout(() => {
                updateCameraDevicesList();
                updateAudioDevicesList();
                updateAudioOutputButtonState();
            }, 800);
        });
    }
}

// ==========================================
// AUDIO OUTPUT QUICK-SWITCH (controls bar)
// ==========================================

/**
 * Refreshes the audioOutputBtn visibility and icon to reflect the
 * currently selected audio output device (or hide when unsupported).
 */
export function updateAudioOutputButtonState() {
    const btn = document.getElementById('audioOutputBtn');
    const iconEl = document.getElementById('audioOutputBtnIcon');
    if (!btn) return;

    const supported = typeof HTMLMediaElement !== 'undefined' && 'setSinkId' in HTMLMediaElement.prototype;
    if (!supported || state.availableAudioOutputDevices.length === 0) {
        btn.style.display = 'none';
        return;
    }

    btn.style.display = 'flex';

    // Determine current device label to pick icon
    const activeDevice = state.availableAudioOutputDevices.find(
        d => d.deviceId === state.activeAudioOutputDeviceId
    );
    const label = (activeDevice?.label || '').toLowerCase();
    if (iconEl) {
        if (label.includes('bluetooth') || label.includes('wireless') || label.includes('bt')) {
            iconEl.textContent = 'bluetooth_audio';
        } else if (label.includes('headset') || label.includes('headphone') || label.includes('earphone')) {
            iconEl.textContent = 'headset';
        } else if (label.includes('earpiece') || label.includes('ear speaker')) {
            iconEl.textContent = 'hearing';
        } else {
            iconEl.textContent = 'volume_up';
        }
    }
}

/**
 * Opens the floating audio output picker anchored above audioOutputBtn.
 * Builds a list of available output devices and the active state indicator.
 */
export function showAudioOutputQuickPick() {
    const picker = document.getElementById('audioOutputPicker');
    const routeList = document.getElementById('aopRouteList');
    const countEl = document.getElementById('aopDeviceCount');
    if (!picker || !routeList) return;

    // Toggle close if already open
    if (picker.style.display !== 'none') {
        picker.style.display = 'none';
        return;
    }

    const devices = state.availableAudioOutputDevices;
    if (countEl) {
        countEl.textContent = devices.length > 0 ? `${devices.length} device${devices.length === 1 ? '' : 's'}` : '';
    }

    routeList.innerHTML = '';

    // Build device rows
    devices.forEach(device => {
        const label = device.label || 'Unknown Speaker';
        const isActive = device.deviceId === state.activeAudioOutputDeviceId ||
            (!state.activeAudioOutputDeviceId && device.deviceId === 'default');
        const lc = label.toLowerCase();
        let icon = 'volume_up';
        if (lc.includes('bluetooth') || lc.includes('wireless') || lc.includes('bt')) icon = 'bluetooth_audio';
        else if (lc.includes('headset') || lc.includes('headphone') || lc.includes('earphone')) icon = 'headset';
        else if (lc.includes('earpiece') || lc.includes('ear speaker')) icon = 'hearing';

        const row = document.createElement('button');
        row.className = 'aop-row' + (isActive ? ' active' : '');
        row.type = 'button';
        row.innerHTML = `
            <span class="material-symbols-outlined aop-icon">${icon}</span>
            <span class="aop-label">${label}</span>
            ${isActive ? '<span class="material-symbols-outlined aop-check">check_circle</span>' : ''}
        `;
        row.addEventListener('click', async (e) => {
            e.stopPropagation();
            picker.style.display = 'none';
            await selectAudioOutputDevice(device.deviceId);
            updateAudioOutputButtonState();
        });
        routeList.appendChild(row);
    });

    // If no devices at all, show a fallback message
    if (devices.length === 0) {
        routeList.innerHTML = '<p style="padding:10px 14px;color:rgba(255,255,255,0.5);font-size:0.82rem;">No output devices detected</p>';
    }

    picker.style.display = 'flex';

    // Close when clicking anywhere else
    const closeOutside = (e) => {
        if (!picker.contains(e.target) && e.target.id !== 'audioOutputBtn' && e.target.id !== 'audioOutputBtnIcon') {
            picker.style.display = 'none';
            document.removeEventListener('click', closeOutside, true);
        }
    };
    setTimeout(() => document.addEventListener('click', closeOutside, true), 50);
}

// ==========================================
// DATA SAVER / LOW-BANDWIDTH MODE
// ==========================================

/**
 * Toggles data saver mode on or off.
 * When active, it unsubscribes from all remote video tracks, prompts off local camera,
 * and renders avatar placeholders only.
 */
export function toggleDataSaverMode(forceState) {
    const newState = (forceState !== undefined) ? forceState : !state.isDataSaverMode;
    state.isDataSaverMode = newState;

    try {
        localStorage.setItem('lavie_data_saver', newState ? 'true' : 'false');
    } catch (_) {}

    // 1. Unsubscribe/Resubscribe from remote video tracks in LiveKit (exempting screen share presentations)
    if (state.currentRoom) {
        state.currentRoom.remoteParticipants.forEach(participant => {
            participant.videoTrackPublications.forEach(pub => {
                const isScreenShare = pub.source === Track.Source.ScreenShare || pub.source === 'screen_share';
                if (!isScreenShare) {
                    pub.setSubscribed(!newState);
                } else {
                    pub.setSubscribed(true);
                }
            });
        });
    }

    // 2. If enabling data saver and camera is currently on, turn off local camera to save upload bandwidth
    if (newState && state.isVideoEnabled) {
        const toggleVideoBtn = document.getElementById('toggleVideoBtn');
        if (toggleVideoBtn && toggleVideoBtn.classList.contains('active')) {
            toggleVideoBtn.click();
            showToast("Camera disabled to save data");
        }
    }

    // 3. Update DOM classes
    const videoGrid = document.getElementById('videoGrid');
    if (videoGrid) {
        if (newState) {
            videoGrid.classList.add('data-saver');
        } else {
            videoGrid.classList.remove('data-saver');
        }
    }
    if (newState) {
        document.body.classList.add('data-saver-active');
    } else {
        document.body.classList.remove('data-saver-active');
    }

    // 4. Update UI Buttons
    const toggleDataSaverBtn = document.getElementById('toggleDataSaverBtn');
    if (toggleDataSaverBtn) {
        if (newState) {
            toggleDataSaverBtn.classList.add('saver-active');
            toggleDataSaverBtn.innerHTML = '<span class="material-symbols-outlined" style="color: #f59e0b;">data_saver_on</span> Data Saver (ON)';
        } else {
            toggleDataSaverBtn.classList.remove('saver-active');
            toggleDataSaverBtn.innerHTML = '<span class="material-symbols-outlined">data_saver_on</span> Data Saver';
        }
    }

    const mobileSheetDataSaverBtn = document.getElementById('mobileSheetDataSaverBtn');
    if (mobileSheetDataSaverBtn) {
        mobileSheetDataSaverBtn.style.color = newState ? '#f59e0b' : '';
    }

    const settingsDataSaverToggleBtn = document.getElementById('settingsDataSaverToggleBtn');
    if (settingsDataSaverToggleBtn) {
        settingsDataSaverToggleBtn.textContent = newState ? 'Enabled' : 'Disabled';
        settingsDataSaverToggleBtn.style.color = newState ? '#10b981' : 'white';
    }

    // 5. Update Status Banner
    updateDataSaverBanner();

    showToast(newState ? "Data Saver ON (Audio Only)" : "Data Saver OFF (Full Video)");
    return newState;
}

export function updateDataSaverBanner() {
    let banner = document.getElementById('dataSaverActiveBanner');
    if (state.isDataSaverMode) {
        if (!banner) {
            banner = document.createElement('div');
            banner.id = 'dataSaverActiveBanner';
            banner.className = 'data-saver-pill';
            banner.innerHTML = `
                <span class="material-symbols-outlined" style="font-size: 1rem; color: #f59e0b;">bolt</span>
                <span>Data Saver: ON (Audio Only)</span>
                <button id="disableDataSaverPillBtn" class="pill-close-btn" title="Turn off Data Saver">&times;</button>
            `;
            const meetingInfo = document.getElementById('meetingInfo');
            if (meetingInfo) {
                meetingInfo.appendChild(banner);
                const pillBtn = document.getElementById('disableDataSaverPillBtn');
                if (pillBtn) {
                    pillBtn.addEventListener('click', (e) => {
                        e.stopPropagation();
                        toggleDataSaverMode(false);
                    });
                }
            }
        }
        if (banner) banner.style.display = 'inline-flex';
    } else {
        if (banner) banner.style.display = 'none';
    }
}
