// ==========================================
// CENTRALIZED MUTABLE STATE FOR LA-VIE CONFERENCE
// ==========================================

export const state = {
    // WebRTC Room & User
    currentRoom: null,
    userName: "Anonymous",
    pendingRoomId: null,
    isMicEnabled: true,
    isVideoEnabled: true,
    isScreenSharing: false,
    currentFacingMode: 'user',
    pinnedWrapperId: null,
    livekitUrlFallback: "wss://lavie-live-bmlbvgd2.livekit.cloud",
    isAdmin: false,
    isHost: false,

    // Devices
    availableVideoDevices: [],
    availableAudioInputDevices: [],
    availableAudioOutputDevices: [],
    activeCameraDeviceId: null,
    activeAudioInputDeviceId: null,
    activeAudioOutputDeviceId: null,

    // Interactivity
    raisedHands: new Set(),
    isHandRaised: false,
    isWhiteboardActive: false,
    isPollQaOpen: false,

    // Polls & Q&A
    activePoll: null,
    localVotedOption: null,
    qaQuestions: [],
    localQaUpvoted: new Set(),
    newQaCount: 0,

    // Audio & Video Processing / Recording
    mediaRecorder: null,
    recordedChunks: [],
    recordingAudioContext: null,
    recordingDestinationNode: null,
    audioSourceNodes: new Map(),
    backgroundProcessor: null,
    krispFilter: null,
    isNoiseCancellationEnabled: false,

    // Active Speaker & DOM Performance Maps
    activeSpeakerSet: new Set(),
    participantOrder: [],
    speakingAnalysers: new Map(),
    sharedAudioContext: null,
    participantDomMap: new Map(),

    // Streaming & Subscription
    currentSubscription: { plan: 'free', can_multistream: false, max_destinations: 0, name: 'Free Tier' },
    currentDestinations: [],
    activeStreamEgressId: null,

    // Data Saver & Live Captions
    isDataSaverMode: false,
    isCaptionsEnabled: false,
    captionsLanguage: 'en-US',

    // Green Room Initial Choices
    greenRoomSettings: {
        cameraDeviceId: null,
        audioDeviceId: null,
        isMicEnabled: true,
        isVideoEnabled: true
    }
};
