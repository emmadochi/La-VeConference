// ==========================================
// IN-MEETING CHAT MODULE
// ==========================================
import { state } from "./state.js";

export function sendMessage() {
    const chatInput = document.getElementById('chatInput');
    if (!chatInput) return;
    const text = chatInput.value.trim();
    if (text && state.currentRoom && state.currentRoom.state === 'connected') {
        const payload = JSON.stringify({ type: 'chat', sender: state.userName, text: text });
        const data = new TextEncoder().encode(payload);
        state.currentRoom.localParticipant.publishData(data, { reliable: true });
        appendMessage(state.userName + " (You)", text, true);
        chatInput.value = '';
    }
}

export function appendMessage(sender, text, isSelf) {
    const chatMessages = document.getElementById('chatMessages');
    if (!chatMessages) return;
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

export function appendSystemMessage(text) {
    const chatMessages = document.getElementById('chatMessages');
    if (!chatMessages) return;
    const msgDiv = document.createElement('div');
    msgDiv.className = 'chat-system';
    msgDiv.textContent = text;
    chatMessages.appendChild(msgDiv);
    chatMessages.scrollTop = chatMessages.scrollHeight;
}

export function initChatListeners() {
    const sendBtn = document.getElementById('sendBtn');
    const chatInput = document.getElementById('chatInput');
    if (sendBtn) sendBtn.addEventListener('click', sendMessage);
    if (chatInput) {
        chatInput.addEventListener('keypress', (e) => { 
            if (e.key === 'Enter') sendMessage(); 
        });
    }
}
