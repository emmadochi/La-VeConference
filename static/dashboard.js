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

// Listen for auth state
window.addEventListener('authStateChanged', (e) => {
    currentUser = e.detail.user;
    if (currentUser) {
        fetchMeetings();
    } else {
        meetingList.innerHTML = '';
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
            
            li.innerHTML = `
                <div class="meeting-item-details">
                    <strong>${data.title || 'Untitled Meeting'}</strong>
                    <span>${formatDate(data.scheduledTime)} &bull; ${data.roomId}</span>
                </div>
                <button onclick="window.location.href='?room=${data.roomId}'">Start</button>
            `;
            meetingList.appendChild(li);
        });
    } catch (err) {
        console.error("Error fetching meetings:", err);
        meetingList.innerHTML = '<p class="error-text">Failed to load meetings.</p>';
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
        
        scheduleMsg.style.color = "#22c55e";
        scheduleMsg.textContent = "Meeting scheduled! Link: ?room=" + roomId;
        
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
