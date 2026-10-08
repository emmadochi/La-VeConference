// ==========================================
// UTILITY FUNCTIONS & HELPERS
// ==========================================
import { state } from "./state.js";

let _toastElement = null;
let _toastTimeout = null;

function _getToastEl() {
    if (!_toastElement) {
        _toastElement = document.createElement('div');
        _toastElement.style.cssText = `
            position: fixed; bottom: 120px; left: 50%; transform: translateX(-50%);
            color: white; padding: 12px 24px; border-radius: 12px; z-index: 99999;
            font-weight: 600; box-shadow: 0 10px 25px rgba(0,0,0,0.5);
            text-align: center; max-width: 90%; pointer-events: none;
            transition: opacity 0.4s ease; opacity: 0; font-family: 'Inter', sans-serif;
        `;
        document.body.appendChild(_toastElement);
    }
    return _toastElement;
}

export function showToast(message, isError = false) {
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
 */
export async function copyTextToClipboard(text, successMsg = 'Copied to clipboard!', errorMsg = 'Failed to copy.') {
    if (!text) {
        showToast(errorMsg, true);
        return false;
    }

    let copied = false;

    // 1. Modern navigator.clipboard API
    if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
        try {
            await navigator.clipboard.writeText(text);
            copied = true;
        } catch (err) {
            console.warn('navigator.clipboard.writeText failed, trying fallback...', err);
        }
    }

    // 2. Fallback using document.execCommand('copy')
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
        showToast(successMsg);
        return true;
    } else {
        try {
            window.prompt('Copy to clipboard (Ctrl+C / Cmd+C):', text);
            showToast(successMsg);
            return true;
        } catch (e) {
            showToast(errorMsg, true);
            return false;
        }
    }
}
window.copyTextToClipboard = copyTextToClipboard;

export function getMeetingShareUrl(rId) {
    const rid = rId || (state.currentRoom ? state.currentRoom.name : null) || state.pendingRoomId || (new URLSearchParams(window.location.search)).get('room') || '';
    const origin = window.location.origin;
    const pathname = window.location.pathname;
    if (rid) {
        return `${origin}${pathname}?room=${encodeURIComponent(rid)}`;
    }
    return window.location.href;
}
window.getMeetingShareUrl = getMeetingShareUrl;

export function copyMeetingLink(rId) {
    const url = getMeetingShareUrl(rId);
    return copyTextToClipboard(url, 'Meeting link copied to clipboard!');
}
window.copyMeetingLink = copyMeetingLink;

export function copyMeetingCode(rId) {
    const rid = rId || (state.currentRoom ? state.currentRoom.name : null) || state.pendingRoomId || (new URLSearchParams(window.location.search)).get('room') || '';
    return copyTextToClipboard(rid, 'Meeting code copied to clipboard!');
}
window.copyMeetingCode = copyMeetingCode;

export function escapeHtml(str) {
    if (!str) return '';
    return str
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
}

/**
 * Translates raw technical WebRTC, network, and permission exceptions into human-friendly messages.
 * Returns null if the error represents an intentional user cancellation (e.g. screen share cancel).
 */
export function formatFriendlyErrorMessage(err) {
    if (!err) return "An unexpected error occurred. Please try again.";
    
    const name = err.name || "";
    const msg = (err.message || err.toString() || "").toLowerCase();
    
    // 1. Screen sharing or permission prompt cancellations
    if (name === 'AbortError' || 
        msg.includes('cancelled') || 
        msg.includes('canceled') || 
        (name === 'NotAllowedError' && (msg.includes('permission denied by system') || msg.includes('user cancelled')))) {
        return null; // Silent dismissal
    }
    
    // 2. Camera or microphone permission denied
    if (name === 'NotAllowedError' || msg.includes('permission denied') || msg.includes('notallowederror')) {
        return "Camera or microphone access was denied. Please allow camera and microphone access in your browser address bar.";
    }
    
    // 3. Camera or microphone busy / in use by another app
    if (name === 'NotReadableError' || msg.includes('could not start video source') || msg.includes('notreadableerror') || msg.includes('device in use') || msg.includes('starting video input failed')) {
        return "Your camera or microphone is in use by another application (such as Zoom, Teams, or Camera). Please close it and retry.";
    }
    
    // 4. Hardware device not found
    if (name === 'NotFoundError' || msg.includes('requested device not found') || msg.includes('notfounderror')) {
        return "No camera or microphone was detected on this device.";
    }
    
    // 5. ICE / WebRTC Media Connection Failure
    if (msg.includes('mediaconnectexception') || msg.includes('ice connectivity') || msg.includes('peerconnection') || msg.includes('connection timed out')) {
        return "Unable to establish media connection. Your network connection is too slow or restricting WebRTC video traffic. Please switch to a stronger connection or Wi-Fi.";
    }
    
    // 6. Network offline or server unreachable
    if (msg.includes('failed to fetch') || msg.includes('networkerror') || msg.includes('socketexception') || msg.includes('failed host lookup')) {
        return "Unable to connect to the conference server. Please check your internet connection and try again.";
    }
    
    // 7. Room locked
    if (msg.includes('room_locked') || msg.includes('locked by the host')) {
        return "This meeting has been locked by the host. No new participants may join.";
    }
    
    // 8. Server 500 error
    if (msg.includes('status 50') || msg.includes('internal server error')) {
        return "The conference server encountered a temporary error. Please try again in a few moments.";
    }
    
    // 9. Meeting not found
    if (msg.includes('status 404') || msg.includes('not found')) {
        return "Meeting not found. Please double-check your meeting ID or link.";
    }
    
    // Generic fallback: strip technical prefixes
    let clean = (err.message || err.toString() || "Connection failed")
        .replace(/^Error:\s*/i, '')
        .replace(/^Exception:\s*/i, '')
        .replace(/^LiveKit Exception:\s*/i, '');
        
    return clean;
}
window.formatFriendlyErrorMessage = formatFriendlyErrorMessage;

