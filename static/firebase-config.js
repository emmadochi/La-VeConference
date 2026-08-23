import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js";
import { getAuth, onAuthStateChanged, signInWithEmailAndPassword, createUserWithEmailAndPassword, sendPasswordResetEmail, signOut, updateProfile, GoogleAuthProvider, signInWithPopup } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-auth.js";
import { initializeFirestore, collection, addDoc, query, where, getDocs, orderBy, doc, onSnapshot, updateDoc } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-firestore.js";

const firebaseConfig = {
  apiKey: "AIzaSyAl5ce-oGNLAfYtvmxuez8dLzIQsM8QNjM",
  authDomain: "lifeconference-e0add.firebaseapp.com",
  projectId: "lifeconference-e0add",
  storageBucket: "lifeconference-e0add.firebasestorage.app",
  messagingSenderId: "563333021985",
  appId: "1:563333021985:web:4d61abbefd7751b8a13e60",
  measurementId: "G-C9JMDF570P"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = initializeFirestore(app, {
    experimentalForceLongPolling: true
});

window.firebaseAuth = auth;
window.firebaseDb = db;

// Export functions for global use
export const fbFunctions = {
    onAuthStateChanged,
    signInWithEmailAndPassword,
    createUserWithEmailAndPassword,
    sendPasswordResetEmail,
    signOut,
    updateProfile,
    GoogleAuthProvider,
    signInWithPopup,
    collection,
    addDoc,
    query,
    where,
    getDocs,
    orderBy,
    doc,
    onSnapshot,
    updateDoc
};
window.fbFunctions = fbFunctions;
