// ==========================================
// CALL RECORDING MODULE
// ==========================================
import { state } from "./state.js";
import { showToast } from "./utils.js";

export async function startRecording() {
    if (!state.currentRoom) return;
    try {
        state.recordingAudioContext = new (window.AudioContext || window.webkitAudioContext)();
        state.recordingDestinationNode = state.recordingAudioContext.createMediaStreamDestination();
        state.audioSourceNodes.clear();
        state.recordedChunks = [];

        const connectTrack = (trackSid, mediaStreamTrack) => {
            if (mediaStreamTrack && !state.audioSourceNodes.has(trackSid)) {
                const source = state.recordingAudioContext.createMediaStreamSource(new MediaStream([mediaStreamTrack]));
                source.connect(state.recordingDestinationNode);
                state.audioSourceNodes.set(trackSid, source);
            }
        };

        if (state.currentRoom.localParticipant) {
            state.currentRoom.localParticipant.audioTrackPublications.forEach(pub => {
                if (pub.track && pub.track.mediaStreamTrack) connectTrack(pub.trackSid, pub.track.mediaStreamTrack);
            });
        }
        state.currentRoom.remoteParticipants.forEach(p => {
            p.audioTrackPublications.forEach(pub => {
                if (pub.track && pub.track.mediaStreamTrack) connectTrack(pub.trackSid, pub.track.mediaStreamTrack);
            });
        });

        const options = { mimeType: 'audio/webm' };
        state.mediaRecorder = new MediaRecorder(state.recordingDestinationNode.stream, options);
        state.mediaRecorder.ondataavailable = (e) => { 
            if (e.data.size > 0) state.recordedChunks.push(e.data); 
        };
        state.mediaRecorder.start(1000);

        const toggleRecordBtn = document.getElementById('toggleRecordBtn');
        if (toggleRecordBtn) {
            toggleRecordBtn.classList.add('recording');
            const txt = toggleRecordBtn.querySelector('.btn-text');
            if (txt) txt.textContent = 'Stop Rec';
        }
        showToast("Recording started");
    } catch(err) {
        console.error("Recording error:", err);
        showToast("Failed to start recording", true);
    }
}

export function stopRecording() {
    if (state.mediaRecorder && state.mediaRecorder.state !== 'inactive') {
        try { state.mediaRecorder.stop(); } catch(e) {}
    }
    state.mediaRecorder = null;
    if (state.recordingAudioContext) {
        try { state.recordingAudioContext.close(); } catch(e) {}
        state.recordingAudioContext = null;
    }
    state.recordingDestinationNode = null;
    state.audioSourceNodes.clear();

    const toggleRecordBtn = document.getElementById('toggleRecordBtn');
    if (toggleRecordBtn) {
        toggleRecordBtn.classList.remove('recording');
        const txt = toggleRecordBtn.querySelector('.btn-text');
        if (txt) txt.textContent = 'Record';
    }
}

export function saveRecording() {
    if (state.recordedChunks.length === 0) return;
    const blob = new Blob(state.recordedChunks, { type: 'audio/webm' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    document.body.appendChild(a);
    a.style.display = 'none';
    a.href = url;
    a.download = `Meeting_Recording_${Date.now()}.webm`;
    a.click();
    URL.revokeObjectURL(url);
    showToast("Recording saved!");
    state.recordedChunks = [];
}
