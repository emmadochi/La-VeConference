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
const authFullName = document.getElementById("authFullName");
const authEmail = document.getElementById("authEmail");
const authPassword = document.getElementById("authPassword");
const signupOtpSection = document.getElementById("signupOtpSection");
const signupOtpTargetEmail = document.getElementById("signupOtpTargetEmail");
const signupOtpInput = document.getElementById("signupOtpInput");
const resendSignupOtpBtn = document.getElementById("resendSignupOtpBtn");
const changeSignupEmailLink = document.getElementById("changeSignupEmailLink");
const authSubmitBtn = document.getElementById("authSubmitBtn");
const googleAuthBtn = document.getElementById("googleAuthBtn");
const switchAuthMode = document.getElementById("switchAuthMode");
const authError = document.getElementById("authError");
const authSuccess = document.getElementById("authSuccess");
const forgotPasswordLink = document.getElementById("forgotPasswordLink");
const forgotPasswordContainer = document.getElementById("forgotPasswordContainer");

// State
let isLoginMode = true;
let isSignupOtpStep = false;
let signupOtpCooldown = 0;
let signupOtpTimer = null;

function clearSignupOtpState() {
    isSignupOtpStep = false;
    if (signupOtpTimer) {
        clearInterval(signupOtpTimer);
        signupOtpTimer = null;
    }
    signupOtpCooldown = 0;
    if (signupOtpSection) signupOtpSection.style.display = "none";
    if (signupOtpInput) signupOtpInput.value = "";
    if (resendSignupOtpBtn) {
        resendSignupOtpBtn.disabled = false;
        resendSignupOtpBtn.textContent = "Resend code";
    }
}

function startSignupOtpCooldown(seconds = 45) {
    if (signupOtpTimer) clearInterval(signupOtpTimer);
    signupOtpCooldown = seconds;
    const updateBtn = () => {
        if (!resendSignupOtpBtn) return;
        if (signupOtpCooldown > 0) {
            resendSignupOtpBtn.disabled = true;
            resendSignupOtpBtn.textContent = `Resend (${signupOtpCooldown}s)`;
        } else {
            resendSignupOtpBtn.disabled = false;
            resendSignupOtpBtn.textContent = "Resend code";
            clearInterval(signupOtpTimer);
            signupOtpTimer = null;
        }
    };
    updateBtn();
    signupOtpTimer = setInterval(() => {
        signupOtpCooldown--;
        updateBtn();
    }, 1000);
}

// Utility to open modal
function openAuthModal(loginMode = true) {
    isLoginMode = loginMode;
    clearSignupOtpState();
    modalTitle.textContent = isLoginMode ? "Log In" : "Sign Up";
    authSubmitBtn.textContent = isLoginMode ? "Submit" : "Send Verification Code";
    switchAuthMode.textContent = isLoginMode ? "Sign up" : "Log in";
    switchAuthMode.parentElement.firstChild.textContent = isLoginMode ? "Don't have an account? " : "Already have an account? ";
    if (authFullName) {
        authFullName.style.display = isLoginMode ? "none" : "block";
        authFullName.disabled = false;
    }
    if (authEmail) authEmail.disabled = false;
    if (authPassword) authPassword.disabled = false;
    if (forgotPasswordContainer) {
        forgotPasswordContainer.style.display = isLoginMode ? "block" : "none";
    }
    if (authError) authError.textContent = "";
    if (authSuccess) {
        authSuccess.textContent = "";
        authSuccess.style.display = "none";
    }
    authModal.style.display = "flex";
}
window.openAuthModal = openAuthModal;

// Event Listeners
loginBtn.addEventListener("click", () => openAuthModal(true));
signupBtn.addEventListener("click", () => openAuthModal(false));

if (forgotPasswordLink) {
    forgotPasswordLink.addEventListener("click", async (e) => {
        e.preventDefault();
        const email = authEmail.value.trim();
        if (authError) authError.textContent = "";
        if (authSuccess) {
            authSuccess.textContent = "";
            authSuccess.style.display = "none";
        }

        if (!email) {
            if (authError) authError.textContent = "Please enter your email above to receive a reset link.";
            authEmail.focus();
            return;
        }

        try {
            forgotPasswordLink.textContent = "Sending link...";
            await fbFunctions.sendPasswordResetEmail(auth, email);
            if (authSuccess) {
                authSuccess.textContent = `Password reset link sent to ${email}! Check your inbox.`;
                authSuccess.style.display = "block";
            }
        } catch (err) {
            if (authError) authError.textContent = err.message || "Failed to send password reset email.";
        } finally {
            forgotPasswordLink.textContent = "Forgot password?";
        }
    });
}

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

async function sendWebSignupOtp(email, fullName) {
    const res = await fetch("/api/auth/send-signup-otp", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, display_name: fullName }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
        throw new Error(data.detail || "Failed to send verification code.");
    }
    return data;
}

if (changeSignupEmailLink) {
    changeSignupEmailLink.addEventListener("click", (e) => {
        e.preventDefault();
        clearSignupOtpState();
        if (authEmail) authEmail.disabled = false;
        if (authPassword) authPassword.disabled = false;
        if (authFullName) authFullName.disabled = false;
        if (authSuccess) authSuccess.style.display = "none";
        if (authError) authError.textContent = "";
        authSubmitBtn.textContent = "Send Verification Code";
    });
}

if (resendSignupOtpBtn) {
    resendSignupOtpBtn.addEventListener("click", async () => {
        if (resendSignupOtpBtn.disabled) return;
        const email = authEmail.value.trim();
        const fullName = authFullName ? authFullName.value.trim() : "";
        authError.textContent = "";
        try {
            resendSignupOtpBtn.disabled = true;
            resendSignupOtpBtn.textContent = "Sending...";
            await sendWebSignupOtp(email, fullName);
            startSignupOtpCooldown(45);
            if (authSuccess) {
                authSuccess.textContent = `A new 6-digit code was sent to ${email}.`;
                authSuccess.style.display = "block";
            }
        } catch (err) {
            authError.textContent = err.message || "Failed to resend code.";
            resendSignupOtpBtn.disabled = false;
            resendSignupOtpBtn.textContent = "Resend code";
        }
    });
}

// Auth Submit
authSubmitBtn.addEventListener("click", async () => {
    const email = authEmail.value.trim();
    const password = authPassword.value.trim();
    const fullName = authFullName ? authFullName.value.trim() : "";

    if (!email || !password) {
        authError.textContent = "Please enter email and password.";
        return;
    }

    if (!isLoginMode && password.length < 6) {
        authError.textContent = "Password must be at least 6 characters long.";
        return;
    }

    authSubmitBtn.disabled = true;
    authSubmitBtn.textContent = "Processing...";
    authError.textContent = "";
    if (authSuccess) authSuccess.style.display = "none";

    try {
        if (isLoginMode) {
            await fbFunctions.signInWithEmailAndPassword(auth, email, password);
            authModal.style.display = "none";
            authEmail.value = "";
            authPassword.value = "";
        } else if (!isSignupOtpStep) {
            // Step 1: Send 6-digit OTP to email
            await sendWebSignupOtp(email, fullName);
            isSignupOtpStep = true;
            if (authEmail) authEmail.disabled = true;
            if (authPassword) authPassword.disabled = true;
            if (authFullName) authFullName.disabled = true;
            if (signupOtpTargetEmail) signupOtpTargetEmail.textContent = email;
            if (signupOtpSection) signupOtpSection.style.display = "block";
            startSignupOtpCooldown(45);
            if (authSuccess) {
                authSuccess.textContent = "Verification code sent! Check your email inbox.";
                authSuccess.style.display = "block";
            }
            if (signupOtpInput) signupOtpInput.focus();
        } else {
            // Step 2: Verify 6-digit OTP & create verified account
            const otp = signupOtpInput ? signupOtpInput.value.trim() : "";
            if (otp.length !== 6) {
                throw new Error("Please enter the 6-digit verification code.");
            }
            const res = await fetch("/api/auth/verify-signup-otp", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    email,
                    otp,
                    password,
                    display_name: fullName || email.split("@")[0],
                }),
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok) {
                throw new Error(data.detail || "Invalid verification code.");
            }
            await fbFunctions.signInWithEmailAndPassword(auth, email, password);
            clearSignupOtpState();
            authModal.style.display = "none";
            if (authFullName) authFullName.value = "";
            authEmail.value = "";
            authPassword.value = "";
        }
    } catch (error) {
        authError.textContent = error.message;
    } finally {
        authSubmitBtn.disabled = false;
        authSubmitBtn.textContent = isLoginMode
            ? "Submit"
            : (isSignupOtpStep ? "Verify & Create Account" : "Send Verification Code");
    }
});

// Google Auth
if (googleAuthBtn) {
    googleAuthBtn.addEventListener("click", async () => {
        try {
            googleAuthBtn.disabled = true;
            authError.textContent = "";
            const provider = new fbFunctions.GoogleAuthProvider();
            
            const result = await fbFunctions.signInWithPopup(auth, provider);
            
            // Get the Google Access Token if available
            const credential = fbFunctions.GoogleAuthProvider.credentialFromResult(result);
            if (credential && credential.accessToken) {
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

// Auth Ready tracking
let _authReadyResolved = false;
let _authResolvers = [];

export function waitForAuthInit() {
    if (_authReadyResolved) {
        return Promise.resolve(auth.currentUser);
    }
    return new Promise((resolve) => {
        _authResolvers.push(resolve);
    });
}
window.waitForAuthInit = waitForAuthInit;

// Logout
logoutBtn.addEventListener("click", async () => {
    await fbFunctions.signOut(auth);
});

// Global state listener
fbFunctions.onAuthStateChanged(auth, (user) => {
    _authReadyResolved = true;
    while (_authResolvers.length > 0) {
        const resolve = _authResolvers.shift();
        try { resolve(user); } catch (e) { console.error(e); }
    }

    const dashboardSection = document.getElementById("dashboardSection");
    const scheduleMeetingBtn = document.getElementById("scheduleMeetingBtn");
    const preJoinModal = document.getElementById("preJoinModal");
    const visitorHero = document.getElementById("visitorHero");
    const visitorHeroCard = document.getElementById("visitorHeroCard");
    const workspaceGreeting = document.getElementById("workspaceGreeting");
    const greetingNameText = document.getElementById("greetingNameText");
    const workspaceTimeGreeting = document.getElementById("workspaceTimeGreeting");
    const workspaceQuickBar = document.getElementById("workspaceQuickBar");
    const quickPersonalRoomCode = document.getElementById("quickPersonalRoomCode");
    const navUserAvatar = document.getElementById("navUserAvatar");
    const dropdownUserAvatar = document.getElementById("dropdownUserAvatar");
    const dropdownUserName = document.getElementById("dropdownUserName");
    const dropdownUserEmail = document.getElementById("dropdownUserEmail");
    
    if (user) {
        authSection.style.display = "none";
        userSection.style.display = "flex";
        
        const fullName = user.displayName || (user.email ? user.email.split("@")[0] : "User");
        const firstName = fullName.split(" ")[0];
        navUserName.textContent = fullName;
        
        // Compute Initials
        const parts = fullName.trim().split(" ");
        let initials = parts[0][0].toUpperCase();
        if (parts.length > 1 && parts[parts.length - 1].length > 0) {
            initials += parts[parts.length - 1][0].toUpperCase();
        }
        if (navUserAvatar) navUserAvatar.textContent = initials;
        if (dropdownUserAvatar) dropdownUserAvatar.textContent = initials;
        if (dropdownUserName) dropdownUserName.textContent = fullName;
        if (dropdownUserEmail) dropdownUserEmail.textContent = user.email || "";

        // Dismiss guest name modal if user is logged in
        if (preJoinModal) {
            preJoinModal.style.display = "none";
        }
        
        // Workspace Command Center Transition
        if (visitorHero) visitorHero.style.display = "none";
        if (visitorHeroCard) visitorHeroCard.style.display = "none";
        if (workspaceGreeting) workspaceGreeting.style.display = "block";
        if (greetingNameText) greetingNameText.textContent = firstName;
        
        // Time of day greeting
        const hour = new Date().getHours();
        let timeSalutation = "Executive Workspace";
        if (hour < 12) timeSalutation = "Good morning";
        else if (hour < 17) timeSalutation = "Good afternoon";
        else timeSalutation = "Good evening";
        if (workspaceTimeGreeting) workspaceTimeGreeting.textContent = timeSalutation;

        // Personal Quick Room
        const pRoom = `la-vie-${(user.uid || "").substring(0, 6)}`;
        if (quickPersonalRoomCode) quickPersonalRoomCode.textContent = pRoom;
        if (workspaceQuickBar) workspaceQuickBar.style.display = "inline-flex";

        const copyQuickRoomBtn = document.getElementById("copyQuickRoomBtn");
        if (copyQuickRoomBtn) {
            copyQuickRoomBtn.onclick = () => {
                const fullUrl = `${window.location.origin}/?room=${pRoom}`;
                navigator.clipboard.writeText(fullUrl);
                if (window.showToast) window.showToast(`Personal room link copied: ${pRoom}`);
            };
        }

        const adminBtn = document.getElementById("adminBtn");
        if (adminBtn) {
            if (user.email === "la-vie@adminnew.com") {
                adminBtn.style.display = "flex";
            } else {
                adminBtn.style.display = "none";
            }
        }
        
        // Show auth-required elements
        if (dashboardSection) dashboardSection.style.display = "block";
        if (scheduleMeetingBtn) scheduleMeetingBtn.style.display = "flex";
        
        // Dispatch custom event for other scripts
        window.dispatchEvent(new CustomEvent('authStateChanged', { detail: { user } }));
    } else {
        authSection.style.display = "flex";
        userSection.style.display = "none";
        navUserName.textContent = "";
        
        // Restore Visitor Hero
        if (visitorHero) visitorHero.style.display = "block";
        if (visitorHeroCard) visitorHeroCard.style.display = "block";
        if (workspaceGreeting) workspaceGreeting.style.display = "none";
        if (workspaceQuickBar) workspaceQuickBar.style.display = "none";

        // Hide auth-required elements
        if (dashboardSection) dashboardSection.style.display = "none";
        if (scheduleMeetingBtn) scheduleMeetingBtn.style.display = "none";
        
        window.dispatchEvent(new CustomEvent('authStateChanged', { detail: { user: null } }));
    }
});

// User Profile Dropdown handlers
const userProfileBtn = document.getElementById("userProfileBtn");
const userProfileDropdown = document.getElementById("userProfileDropdown");
if (userProfileBtn && userProfileDropdown) {
    userProfileBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        const isOpen = userProfileDropdown.style.display === "flex";
        userProfileDropdown.style.display = isOpen ? "none" : "flex";
    });

    window.addEventListener("click", (e) => {
        if (!userProfileDropdown.contains(e.target) && e.target !== userProfileBtn) {
            userProfileDropdown.style.display = "none";
        }
    });
}

const scheduleFromMenuBtn = document.getElementById("scheduleFromMenuBtn");
if (scheduleFromMenuBtn) {
    scheduleFromMenuBtn.addEventListener("click", () => {
        if (userProfileDropdown) userProfileDropdown.style.display = "none";
        const scheduleModal = document.getElementById("scheduleModal");
        if (scheduleModal) scheduleModal.style.display = "flex";
    });
}

// Utility to get Token
export async function getAuthToken() {
    if (auth.currentUser) {
        return await auth.currentUser.getIdToken();
    }
    return null;
}

