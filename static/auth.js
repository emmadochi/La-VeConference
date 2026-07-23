import { auth, fbFunctions } from "./firebase-config.js";

// DOM Elements
const authSection = document.getElementById("authSection");
const userSection = document.getElementById("userSection");
const navUserName = document.getElementById("navUserName");
const loginBtn = document.getElementById("loginBtn");
const signupBtn = document.getElementById("signupBtn");
const logoutBtn = document.getElementById("logoutBtn");

const authModal = document.getElementById("authModal");
const closeModals = document.querySelectorAll(".close-modal");
const modalTitle = document.getElementById("modalTitle");
const authEmail = document.getElementById("authEmail");
const authPassword = document.getElementById("authPassword");
const authSubmitBtn = document.getElementById("authSubmitBtn");
const googleAuthBtn = document.getElementById("googleAuthBtn");
const switchAuthMode = document.getElementById("switchAuthMode");
const authError = document.getElementById("authError");

// State
let isLoginMode = true;

// Utility to open modal
function openAuthModal(loginMode = true) {
    isLoginMode = loginMode;
    modalTitle.textContent = isLoginMode ? "Log In" : "Sign Up";
    authSubmitBtn.textContent = isLoginMode ? "Submit" : "Create Account";
    switchAuthMode.textContent = isLoginMode ? "Sign up" : "Log in";
    switchAuthMode.parentElement.firstChild.textContent = isLoginMode ? "Don't have an account? " : "Already have an account? ";
    authError.textContent = "";
    authModal.style.display = "flex";
}
window.openAuthModal = openAuthModal;

// Event Listeners
loginBtn.addEventListener("click", () => openAuthModal(true));
signupBtn.addEventListener("click", () => openAuthModal(false));

switchAuthMode.addEventListener("click", (e) => {
    e.preventDefault();
    openAuthModal(!isLoginMode);
});

closeModals.forEach(btn => {
    btn.addEventListener("click", () => {
        btn.closest(".modal-overlay").style.display = "none";
    });
});

// Close modal if clicked outside
window.addEventListener("click", (e) => {
    if (e.target.classList.contains("modal-overlay")) {
        e.target.style.display = "none";
    }
});

// Auth Submit
authSubmitBtn.addEventListener("click", async () => {
    const email = authEmail.value.trim();
    const password = authPassword.value.trim();
    
    if (!email || !password) {
        authError.textContent = "Please enter email and password.";
        return;
    }

    authSubmitBtn.disabled = true;
    authSubmitBtn.textContent = "Processing...";
    authError.textContent = "";

    try {
        if (isLoginMode) {
            await fbFunctions.signInWithEmailAndPassword(auth, email, password);
        } else {
            const userCred = await fbFunctions.createUserWithEmailAndPassword(auth, email, password);
            // Optionally, prompt for a name during signup, but we'll use email prefix for now
            const name = email.split("@")[0];
            await fbFunctions.updateProfile(userCred.user, { displayName: name });
        }
        authModal.style.display = "none";
        authEmail.value = "";
        authPassword.value = "";
    } catch (error) {
        authError.textContent = error.message;
    } finally {
        authSubmitBtn.disabled = false;
        authSubmitBtn.textContent = isLoginMode ? "Submit" : "Create Account";
    }
});

// Google Auth
if (googleAuthBtn) {
    googleAuthBtn.addEventListener("click", async () => {
        try {
            googleAuthBtn.disabled = true;
            authError.textContent = "";
            const provider = new fbFunctions.GoogleAuthProvider();
            provider.addScope('https://www.googleapis.com/auth/calendar.events');
            
            const result = await fbFunctions.signInWithPopup(auth, provider);
            
            // Get the Google Access Token to use with the Calendar API
            const credential = fbFunctions.GoogleAuthProvider.credentialFromResult(result);
            if (credential && credential.accessToken) {
                // Store temporarily in localStorage to be used by the scheduling logic
                localStorage.setItem('google_calendar_token', credential.accessToken);
            }
            
            authModal.style.display = "none";
        } catch (error) {
            authError.textContent = error.message;
        } finally {
            googleAuthBtn.disabled = false;
        }
    });
}

// Logout
logoutBtn.addEventListener("click", async () => {
    await fbFunctions.signOut(auth);
});

// Global state listener
fbFunctions.onAuthStateChanged(auth, (user) => {
    const dashboardSection = document.getElementById("dashboardSection");
    const scheduleMeetingBtn = document.getElementById("scheduleMeetingBtn");
    
    if (user) {
        authSection.style.display = "none";
        userSection.style.display = "flex";
        navUserName.textContent = user.displayName || user.email.split("@")[0];
        
        // Show auth-required elements
        if (dashboardSection) dashboardSection.style.display = "block";
        if (scheduleMeetingBtn) scheduleMeetingBtn.style.display = "flex";
        
        // Dispatch custom event for other scripts
        window.dispatchEvent(new CustomEvent('authStateChanged', { detail: { user } }));
    } else {
        authSection.style.display = "flex";
        userSection.style.display = "none";
        navUserName.textContent = "";
        
        // Hide auth-required elements
        if (dashboardSection) dashboardSection.style.display = "none";
        if (scheduleMeetingBtn) scheduleMeetingBtn.style.display = "none";
        
        window.dispatchEvent(new CustomEvent('authStateChanged', { detail: { user: null } }));
    }
});

// Utility to get Token
export async function getAuthToken() {
    if (auth.currentUser) {
        return await auth.currentUser.getIdToken();
    }
    return null;
}
