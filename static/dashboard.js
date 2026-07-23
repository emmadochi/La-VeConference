import { db, fbFunctions } from "./firebase-config.js";

const scheduleModal = document.getElementById("scheduleModal");
const scheduleTitle = document.getElementById("scheduleTitle");
const scheduleTime = document.getElementById("scheduleTime");
const scheduleAttendees = document.getElementById("scheduleAttendees");
const scheduleSubmitBtn = document.getElementById("scheduleSubmitBtn");
const scheduleMsg = document.getElementById("scheduleMsg");
const meetingList = document.getElementById("meetingList");

// Initialize Flatpickr for the date/time input
if (scheduleTime) {
    flatpickr(scheduleTime, {
        enableTime: true,
        dateFormat: "Y-m-d\\TH:i",
        altInput: true,
        altFormat: "F j, Y at h:i K",
        minDate: "today",
        time_24hr: false
    });
}
let currentUser = null;

let activeRoomUnsubscribe = null;

// Listen for auth state
window.addEventListener('authStateChanged', (e) => {
    currentUser = e.detail.user;
    if (currentUser) {
        fetchMeetings();
        
        // Listen to active room
        const userRef = fbFunctions.doc(db, "users", currentUser.uid);
        activeRoomUnsubscribe = fbFunctions.onSnapshot(userRef, (docSnap) => {
            if (docSnap.exists()) {
                const activeRoom = docSnap.data().active_room;
                const banner = document.getElementById("activeMeetingBanner");
                const roomText = document.getElementById("activeMeetingRoom");
                const rejoinBtn = document.getElementById("rejoinActiveBtn");
                const leaveBtn = document.getElementById("leaveActiveBtn");
                
                if (activeRoom && banner && roomText) {
                    roomText.innerText = activeRoom;
                    banner.style.display = "block";
                    
                    rejoinBtn.onclick = () => {
                        window.location.href = `?room=${activeRoom}`;
                    };
                    
                    leaveBtn.onclick = async () => {
                        try {
                            leaveBtn.innerText = "Clearing...";
                            await fbFunctions.updateDoc(userRef, { active_room: "" });
                            leaveBtn.innerText = "Leave";
                        } catch (err) {
                            console.error(err);
                            leaveBtn.innerText = "Leave";
                        }
                    };
                } else if (banner) {
                    banner.style.display = "none";
                }
            }
        });
    } else {
        meetingList.innerHTML = '';
        if (activeRoomUnsubscribe) activeRoomUnsubscribe();
        const banner = document.getElementById("activeMeetingBanner");
        if (banner) banner.style.display = "none";
    }
});

// Generate random room code: la-vie-[numbers]
function generateRoomCode() {
    return 'la-vie-' + Date.now().toString().substring(7);
}

// Format date
function formatDate(isoString) {
    const d = new Date(isoString);
    return d.toLocaleString([], { weekday: 'short', month: 'short', day: 'numeric', hour: '2-digit', minute:'2-digit' });
}

// Fetch meetings
async function fetchMeetings() {
    if (!currentUser) return;
    
    try {
        const meetingsRef = fbFunctions.collection(db, "meetings");
        const q = fbFunctions.query(meetingsRef, 
            fbFunctions.where("hostId", "==", currentUser.uid),
            fbFunctions.orderBy("scheduledTime", "asc")
        );
        
        const querySnapshot = await fbFunctions.getDocs(q);
        meetingList.innerHTML = '';
        
        if (querySnapshot.empty) {
            meetingList.innerHTML = '<p style="color: var(--text-muted); font-size: 0.9rem;">No upcoming meetings.</p>';
            return;
        }

        querySnapshot.forEach((doc) => {
            const data = doc.data();
            const li = document.createElement("div");
            li.className = "meeting-item";
            
            // Check for E2EE key in localStorage
            const storedKey = localStorage.getItem(`e2ee_${data.roomId}`);
            const hashSuffix = storedKey ? `#${storedKey}` : '';
            
            li.innerHTML = `
                <div class="meeting-item-details">
                    <strong>${data.title || 'Untitled Meeting'}</strong>
                    <span>${formatDate(data.scheduledTime)} &bull; ${data.roomId}</span>
                </div>
                <button onclick="window.location.href='?room=${data.roomId}${hashSuffix}'">Start</button>
            `;
            meetingList.appendChild(li);
        });
    } catch (err) {
        console.error("Error fetching meetings:", err);
        meetingList.innerHTML = '<p class="error-text">Failed to load meetings.</p>';
    }
}

// Helper to create Google Calendar Event
async function createGoogleCalendarEvent(title, startTimeIso, roomId, e2eeKey, attendeeEmails) {
    const token = localStorage.getItem('google_calendar_token');
    if (!token) return false;
    
    const startTime = new Date(startTimeIso);
    const endTime = new Date(startTime.getTime() + 60 * 60 * 1000); // 1 hour duration
    
    const meetingLink = `https://la-vie.lifechangerstouch.org/?room=${roomId}#${e2eeKey}`;
    
    const event = {
        summary: title,
        description: `Join La-Vie Conference:\\n${meetingLink}\\n\\nThis meeting is End-to-End Encrypted.`,
        start: {
            dateTime: startTime.toISOString(),
            timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone
        },
        end: {
            dateTime: endTime.toISOString(),
            timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone
        },
        attendees: attendeeEmails.map(email => ({ email }))
    };

    try {
        const response = await fetch('https://www.googleapis.com/calendar/v3/calendars/primary/events', {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(event)
        });
        
        if (response.ok) {
            console.log('Google Calendar event created successfully.');
            return true;
        } else {
            console.error('Failed to create calendar event:', await response.text());
            return false;
        }
    } catch (e) {
        console.error('Error calling Calendar API', e);
        return false;
    }
}

// Schedule Submit
scheduleSubmitBtn.addEventListener("click", async () => {
    if (!currentUser) return;
    
    const title = scheduleTitle.value.trim();
    const time = scheduleTime.value;
    const attendeesRaw = scheduleAttendees ? scheduleAttendees.value.trim() : "";
    
    if (!title || !time) {
        scheduleMsg.style.color = "#ef4444";
        scheduleMsg.textContent = "Please provide title and time.";
        return;
    }

    const attendeeEmails = attendeesRaw.split(',')
        .map(email => email.trim())
        .filter(email => email.length > 0);

    scheduleSubmitBtn.disabled = true;
    scheduleSubmitBtn.textContent = "Saving...";
    scheduleMsg.textContent = "";

    try {
        const roomId = generateRoomCode();
        // Generate true E2EE key
        const e2eeKey = Array.from(crypto.getRandomValues(new Uint8Array(16)))
            .map(b => b.toString(16).padStart(2, '0')).join('');
        
        // Save to localStorage so host can start it later
        localStorage.setItem(`e2ee_${roomId}`, e2eeKey);

        // Convert the flatpickr local time string to a full ISO string (UTC)
        const scheduledDateObj = new Date(time);
        const scheduledTimeIso = scheduledDateObj.toISOString();

        await fbFunctions.addDoc(fbFunctions.collection(db, "meetings"), {
            hostId: currentUser.uid,
            title: title,
            scheduledTime: scheduledTimeIso,
            roomId: roomId,
            attendeeEmails: attendeeEmails,
            notified: false,
            createdAt: new Date().toISOString()
        });
        
        // Try creating Google Calendar event
        const calSuccess = await createGoogleCalendarEvent(title, scheduledTimeIso, roomId, e2eeKey, attendeeEmails);
        
        scheduleMsg.style.color = "#22c55e";
        scheduleMsg.textContent = calSuccess ? "Scheduled & added to Google Calendar!" : "Meeting scheduled! Link: ?room=" + roomId;
        
        // Reset form after 2 seconds and fetch
        setTimeout(() => {
            scheduleModal.style.display = "none";
            scheduleTitle.value = "";
            scheduleTime.value = "";
            if (scheduleAttendees) scheduleAttendees.value = "";
            scheduleMsg.textContent = "";
            fetchMeetings();
        }, 2000);
        
    } catch (error) {
        console.error("Error scheduling:", error);
        scheduleMsg.style.color = "#ef4444";
        scheduleMsg.textContent = error.message;
    } finally {
        scheduleSubmitBtn.disabled = false;
        scheduleSubmitBtn.textContent = "Save to Dashboard";
    }
});
