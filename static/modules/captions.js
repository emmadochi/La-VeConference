// ==========================================
// LIVE CAPTIONS MODULE (Web Speech API + Data Channel)
// ==========================================
import { state } from "./state.js";
import { showToast } from "./utils.js";

const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;

let recognitionInstance = null;
let restartTimeout = null;
let autoHideTimer = null;

/**
 * Returns true if this browser supports microphone speech-to-text.
 */
export function isSpeechRecognitionSupported() {
    return Boolean(SpeechRecognition);
}

/**
 * Toggles live captions ON or OFF.
 * @param {boolean} [forceState]
 */
export function toggleCaptions(forceState) {
    const newState = (forceState !== undefined) ? forceState : !state.isCaptionsEnabled;
    state.isCaptionsEnabled = newState;

    try {
        localStorage.setItem('lavie_live_captions', newState ? 'true' : 'false');
    } catch (_) {}

    updateCaptionsUI(newState);

    if (newState) {
        showToast("Live Captions Enabled (CC)");
        startSpeechRecognition();
        ensureCaptionsContainer();
    } else {
        showToast("Live Captions Disabled");
        stopSpeechRecognition();
        hideCaptionsContainer();
    }

    return newState;
}

/**
 * Updates button icons and active states for CC buttons across the app.
 */
export function updateCaptionsUI(isActive) {
    const buttons = [
        document.getElementById('toggleCaptionsBtn'),
        document.getElementById('toggleCaptionsDrawerBtn'),
        document.getElementById('mobileSheetCaptionsBtn'),
        document.getElementById('settingsCaptionsToggleBtn')
    ];

    buttons.forEach(btn => {
        if (!btn) return;
        if (isActive) {
            btn.classList.add('active', 'captions-active');
            btn.style.color = '#00E5FF';
            if (btn.id === 'settingsCaptionsToggleBtn') {
                btn.textContent = 'Enabled';
                btn.style.color = '#10b981';
            }
        } else {
            btn.classList.remove('active', 'captions-active');
            btn.style.color = '';
            if (btn.id === 'settingsCaptionsToggleBtn') {
                btn.textContent = 'Disabled';
                btn.style.color = 'white';
            }
        }
    });
}

/**
 * Starts continuous speech recognition for the local user.
 */
export function startSpeechRecognition() {
    if (!isSpeechRecognitionSupported()) {
        console.info("[Captions] Web Speech API not supported on this browser. Local speech will not be transcribed, but incoming captions from other participants will be rendered.");
        return;
    }

    if (!recognitionInstance) {
        try {
            recognitionInstance = new SpeechRecognition();
            recognitionInstance.continuous = true;
            recognitionInstance.interimResults = true;
            recognitionInstance.maxAlternatives = 1;
            recognitionInstance.lang = state.captionsLanguage || 'en-US';

            recognitionInstance.onresult = (event) => {
                if (!state.isCaptionsEnabled) return;

                let interimTranscript = '';
                let finalTranscript = '';

                for (let i = event.resultIndex; i < event.results.length; ++i) {
                    const transcriptPiece = event.results[i][0].transcript;
                    if (event.results[i].isFinal) {
                        finalTranscript += transcriptPiece;
                    } else {
                        interimTranscript += transcriptPiece;
                    }
                }

                const text = (finalTranscript || interimTranscript).trim();
                if (!text) return;

                const isFinal = Boolean(finalTranscript);
                const senderName = state.userName || 'You';

                // Display on local screen
                renderCaption(senderName, text, isFinal, true);

                // Broadcast over LiveKit data channel
                broadcastCaption(senderName, text, isFinal);
            };

            recognitionInstance.onerror = (event) => {
                // Ignore silent intervals or user pause
                if (event.error !== 'no-speech' && event.error !== 'aborted') {
                    console.warn("[Captions] Speech Recognition error:", event.error);
                }
            };

            recognitionInstance.onend = () => {
                // Keep recognizing continuously as long as captions are turned on
                if (state.isCaptionsEnabled) {
                    if (restartTimeout) clearTimeout(restartTimeout);
                    restartTimeout = setTimeout(() => {
                        try {
                            if (state.isCaptionsEnabled && recognitionInstance) {
                                recognitionInstance.start();
                            }
                        } catch (_) {}
                    }, 400);
                }
            };
        } catch (e) {
            console.error("[Captions] Failed to initialize SpeechRecognition:", e);
            return;
        }
    }

    try {
        recognitionInstance.lang = state.captionsLanguage || 'en-US';
        recognitionInstance.start();
        console.log("[Captions] Speech recognition started in language:", recognitionInstance.lang);
    } catch (_) {
        // Recognition might already be running
    }
}

/**
 * Stops local speech recognition.
 */
export function stopSpeechRecognition() {
    if (restartTimeout) {
        clearTimeout(restartTimeout);
        restartTimeout = null;
    }
    if (recognitionInstance) {
        try {
            recognitionInstance.stop();
        } catch (_) {}
    }
}

/**
 * Broadcasts speaker captions to everyone in the room via LiveKit data channel.
 */
function broadcastCaption(sender, text, isFinal) {
    if (!state.currentRoom || !state.currentRoom.localParticipant) return;

    try {
        const payload = JSON.stringify({
            type: 'caption',
            sender: sender,
            text: text,
            isFinal: isFinal,
            senderId: state.currentRoom.localParticipant.identity,
            timestamp: Date.now()
        });
        const encoded = new TextEncoder().encode(payload);
        state.currentRoom.localParticipant.publishData(encoded, { reliable: false });
    } catch (e) {
        console.warn("[Captions] Failed to broadcast caption data:", e);
    }
}

/**
 * Handles incoming caption data packets from remote participants.
 */
export function handleIncomingCaption(data) {
    if (!state.isCaptionsEnabled || !data || !data.text) return;
    renderCaption(data.sender || 'Participant', data.text, Boolean(data.isFinal), false);
}

/**
 * Renders a caption bubble inside the captions overlay.
 */
export function renderCaption(sender, text, isFinal, isLocal) {
    const container = ensureCaptionsContainer();
    if (!container) return;

    container.style.display = 'flex';

    let bubble = document.getElementById('activeCaptionBubble');
    if (!bubble) {
        bubble = document.createElement('div');
        bubble.id = 'activeCaptionBubble';
        bubble.className = 'caption-bubble';
        container.appendChild(bubble);
    }

    const speakerColor = isLocal ? '#00E5FF' : '#10B981';
    bubble.innerHTML = `
        <span class="caption-speaker" style="color: ${speakerColor}; font-weight: 700; margin-right: 6px;">[${escapeHtml(sender)}]:</span>
        <span class="caption-text ${isFinal ? 'caption-final' : 'caption-interim'}">${escapeHtml(text)}</span>
    `;

    // Auto-dismiss after 4.5 seconds of silence
    if (autoHideTimer) clearTimeout(autoHideTimer);
    autoHideTimer = setTimeout(() => {
        hideCaptionsContainer();
    }, 4500);
}

/**
 * Ensures the floating captions container exists in the DOM.
 */
function ensureCaptionsContainer() {
    let container = document.getElementById('liveCaptionsContainer');
    if (!container) {
        container = document.createElement('div');
        container.id = 'liveCaptionsContainer';
        container.className = 'live-captions-container';
        container.style.display = 'none';

        // Append to mainColumn or videoGrid
        const mainColumn = document.getElementById('mainColumn') || document.body;
        mainColumn.appendChild(container);
    }
    return container;
}

function hideCaptionsContainer() {
    const container = document.getElementById('liveCaptionsContainer');
    if (container) {
        container.style.display = 'none';
        container.innerHTML = '';
    }
}

function escapeHtml(str) {
    if (!str) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}
