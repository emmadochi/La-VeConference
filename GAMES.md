
# LiChat Gaming Ecosystem: Complete Implementation Plan (GAMES.MD)
---

## 1. Executive Summary & Vision

LiChat's mission is to be the primary real-time communication platform for the La-Vie community. Introducing **embedded games** transforms LiChat from a transactional utility (where users only open the app when they receive a message) into a **high-retention social ecosystem** (where users return multiple times a day to engage with friends and peers).

### Core Design Philosophy
1. **Zero Extra Downloads**: Games run natively using Flutter canvas/widgets. No 100MB downloads or heavy game engine bloat.
2. **Frictionless Social Play**: Launch a game right from the chat box in 2 taps.
3. **Turn-Based Asynchronous First**: Friends don't need to be online at the exact same second. You make your move, go about your day, and they get notified to make theirs.
4. **Real-Time Extension**: Real-time multiplayer over LiveKit WebRTC DataChannels during active audio/video calls.

---

## 2. Gaming Paradigms

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            LiChat Game Architecture                         │
├──────────────────────────────────────┬──────────────────────────────────────┤
│    Mode 1: In-Chat Asynchronous      │     Mode 2: In-Call Synchronous      │
│     (iMessage / GamePigeon Style)    │       (Discord Activity Style)       │
├──────────────────────────────────────┼──────────────────────────────────────┤
│ • Interactive chat bubbles in thread │ • Live interactive overlay in calls  │
│ • State stored in Firestore message  │ • State synced via WebRTC DataChannel│
│ • Play turns whenever convenient     │ • Ultra-low latency (<50ms)          │
│ • Push notifications for turns       │ • Collaborative drawing & rapid quiz │
└──────────────────────────────────────┴──────────────────────────────────────┘
```

---

## 3. Launch Game Catalog

### Phase 1 Launch Titles (Fastest to build, highest viral retention)

| Game | Format | Duration | Description |
| :--- | :--- | :--- | :--- |
| **1. Neon Connect 4** | 2-Player Turn-based | 1-3 mins | Classic 7×6 vertical grid. Players take turns dropping neon chips. First to 4-in-a-row wins. Features gravity drop animations and winning streak badges. |
| **2. LiChat Word Duel** | 2-Player Asynchronous | 2-4 mins | Wordle-style competition. Both players guess the same hidden 5-letter word within 6 tries. Winner solved in fewer turns or faster time. |
| **3. Cyber Tic-Tac-Toe** | 2-Player Turn-based | 30 secs | Fast, casual 3×3 and expanded 5×5 grid with glowing emerald and electric lilac symbols. |
| **4. Community Trivia Duel** | 2-Player / Group | 2 mins | 5 rapid-fire questions across Faith/Bible Knowledge, Science, World History, and Pop Culture. Players earn points based on accuracy and speed. |
| **5. Tactical Chess & Checkers** | 2-Player Turn-based | Variable | Standard 8×8 board with legal move highlights, checkmate detection, and state stored in compact FEN/JSON format. |

---

## 4. Technical Architecture & Data Models

### 4.1. Firestore Data Schema

#### In-Chat Game Message Document (`chats/{chatId}/messages/{messageId}`)
```json
{
  "id": "msg_game_89410",
  "chatId": "direct_userA_userB",
  "senderId": "userA_uid",
  "senderName": "Henry Gabriel",
  "type": "game",
  "text": "🎮 Henry started a game of Connect 4!",
  "createdAt": "2026-09-21T16:00:00Z",
  "gameData": {
    "gameType": "connect4",
    "gameId": "c4_982341",
    "status": "in_progress",
    "turnUid": "userB_uid",
    "lastMoveBy": "userA_uid",
    "player1": {
      "uid": "userA_uid",
      "name": "Henry Gabriel",
      "avatar": "https://...",
      "color": "emerald"
    },
    "player2": {
      "uid": "userB_uid",
      "name": "Pastor Temple",
      "avatar": "https://...",
      "color": "lilac"
    },
    "boardState": [
      [0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 0, 0, 0, 0],
      [0, 0, 1, 0, 0, 0, 0],
      [0, 0, 2, 1, 0, 0, 0],
      [1, 2, 2, 1, 2, 0, 0]
    ],
    "winnerUid": null,
    "winningLine": null,
    "moveCount": 6,
    "lastMoveAt": "2026-09-21T16:02:15Z"
  }
}
```

### 4.2. Turn Validation & Security Rules
To prevent unauthorized moves or turn spoofing, Firestore security rules validate:
1. `request.auth.uid == resource.data.gameData.turnUid`: Only the player whose turn it is can commit a move.
2. `request.resource.data.gameData.moveCount == resource.data.gameData.moveCount + 1`: Move counters must increment sequentially.
3. Once `winnerUid != null` or `status == 'completed'`, the document becomes read-only.

---

## 5. UI/UX Specifications

### 5.1. Game Launcher Menu (Chat Attachment Sheet)
Tapping the **`+` (Attachment)** button in `ChatConversationScreen` displays the game launcher tile:
- **Icon**: `Icons.sports_esports_rounded` in Electric Lilac (`#B388FF`).
- **Label**: "Play Game".
- **Picker Sheet**: A bottom drawer displaying game cards with vibrant previews, descriptions, and "Challenge [Peer Name]" button.

### 5.2. Interactive In-Chat Game Bubble (`InChatGameBubble`)
When a game message is rendered in the chat stream:
- **Card Geometry**: 280dp wide, rounded corners (20dp), dark surface background (`#151226`), bordered with a subtle mint/lilac gradient glow.
- **Header**: Mini game icon + Game Name (e.g. `🎮 Connect 4`) + Status pill (`Your Turn 🟢` vs `Waiting for Henry... ⏳`).
- **Body**: Mini interactive board thumbnail rendering the current pieces.
- **Bottom Call-to-Action**:
  - If your turn: High-visibility Emerald button: **"Play Your Turn"**.
  - If peer's turn: Disabled/subtle button: **"Waiting for Opponent"**.
  - If completed: Winner celebration banner with **"Play Again (Rematch)"** button.

### 5.3. Fullscreen Interactive Game Modal
Tapping "Play Your Turn" opens an immersive interactive sheet:
- Top bar showing both player avatars, current score, and active timer (e.g. 60s per turn).
- Large, tactile game board with custom touch interactions (tap column to drop chip, drag piece, or tap letter).
- Haptic feedback (`HapticFeedback.mediumImpact()`) on every move.
- Sound effects: Subtle audio chimes on chip drop, win fanfare, or invalid move using `AudioPlayer`.
- **Victory Ceremony**: When a player wins, triggers fireworks/confetti particles (`confetti` package) with victory sound and 1-tap "Request Rematch".

---

## 6. Directory & Code Architecture

All gaming logic is strictly organized inside `lib/games/`:

```
la_vie_messenger/lib/games/
├── models/
│   ├── game_type.dart             # Enum: connect4, word_duel, tictactoe, trivia, chess
│   ├── game_session.dart          # Base game state model
│   └── game_player.dart           # Player profile & score tracking
├── services/
│   ├── game_service.dart          # Firestore turn dispatch, rematch initiator, forfeit timer
│   └── game_sound_service.dart    # Micro sound effects (move, win, lose, countdown)
├── widgets/
│   ├── game_launcher_sheet.dart   # Bottom sheet to select and challenge peer
│   ├── in_chat_game_bubble.dart   # Custom chat bubble rendering mini-board in message stream
│   ├── game_modal_container.dart  # Modal wrapper with avatars, timer, and rematch
│   └── victory_confetti.dart      # Win celebration particle overlay
└── engines/
    ├── connect_four/
    │   ├── connect_four_engine.dart # 7x6 board state, gravity physics, 4-in-a-row checker
    │   └── connect_four_widget.dart # Animated drop chips with gesture detector
    ├── word_duel/
    │   ├── word_duel_engine.dart    # 5-letter dictionary, color feedback (Green/Yellow/Gray)
    │   └── word_duel_widget.dart    # Keyboard and 6-row tile grid
    ├── tic_tac_toe/
    │   ├── tictactoe_engine.dart    # 3x3 and 5x5 win-line detector
    │   └── tictactoe_widget.dart    # Neon glowing grid
    └── trivia/
        ├── trivia_engine.dart       # Timed question sequencer, score multiplier
        ├── trivia_bank.dart         # Curated question sets (Faith, Science, History)
        └── trivia_widget.dart       # Multi-choice options with real-time feedback
```

---

## 7. Step-by-Step Implementation Roadmap

### Phase 1: Core Framework & In-Chat Bubble Integration
- [ ] Define `game` message type in `chat_service.dart`.
- [ ] Build `InChatGameBubble` widget in `chat_conversation_screen.dart` message stream.
- [ ] Implement `GameService` to handle Firestore state writes (`commitMove`, `forfeitGame`, `requestRematch`).
- [ ] Build `GameLauncherSheet` inside the chat attachment menu (`+` button).

### Phase 2: First Game — Neon Connect 4
- [ ] Implement `ConnectFourEngine` (7×6 matrix, move validation, diagonal/horizontal/vertical win detection).
- [ ] Create `ConnectFourWidget` with smooth gravity drop animations and neon color styling.
- [ ] Wire up push notifications: *"🔴 It's your turn in Connect 4 against [Peer]!"*.

### Phase 3: Second Game — Word Duel (Wordle Style)
- [ ] Create 5-letter offline dictionary list.
- [ ] Implement Wordle comparison logic (Exact match = Green, Present = Yellow, Absent = Dark Gray).
- [ ] Build interactive virtual keyboard with real-time color feedback.

### Phase 4: Third Game — LiChat Trivia Duel
- [ ] Compile curated question database with 4 multiple-choice answers.
- [ ] Implement 15-second per-question timer with score decay for faster answers.
- [ ] Reveal final head-to-head score comparison with winner badge.

### Phase 5: Live In-Call Multiplayer (WebRTC DataChannel)
- [ ] Wire LiveKit `room.localParticipant.publishData()` to broadcast moves live during calls with <50ms latency.
- [ ] Add "Play Together" icon on the active call regulation screen.

---

## 8. Retention & Growth Impact

1. **Daily Active Return Rate**: Asynchronous turn-based games generate **3–7 daily app opens per active match** because every turn sends a direct push notification to the opponent.
2. **Organic Invites**: Users invite outside contacts to download LiChat specifically to challenge them in Word Duel or Connect 4.
3. **Zero Maintenance**: Once published, turn-based board games require zero ongoing server costs because Firestore handles state distribution automatically.
