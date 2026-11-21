# LiChat AI Upgrade Strategy & Roadmap

This document outlines high-impact, utility-focused AI capabilities designed to elevate **LiChat** beyond standard messaging apps like WhatsApp and Telegram. 

Each capability is designed strictly under **Hick's Law** (minimal cognitive load, contextual progressive disclosure, zero UI clutter) and the **80/15/5 Neutral Design Architecture**.

---

## 1. 🎙️ Post-Call AI Summary & Action Items (Flagship Feature)
* **Problem**: After long ministry, team, or personal calls, key decisions and tasks are often forgotten or require manual note-taking.
* **Solution**: An opt-in call assistant leveraging the existing LiveKit WebRTC audio stream.
* **Output**:
  * Private **Call Recap Card** posted in the direct chat after hanging up.
  * **Call Duration & Key Takeaways** (3–4 concise bullet points).
  * **Action Items Checklist** with assigned names (e.g. *"Emmanuel: Send budget draft by Friday"*).
* **Impact**: Positions LiChat as a premier enterprise and ministry communication tool with capabilities WhatsApp and Telegram do not offer natively.

---

## 2. 🔍 Semantic Memory Search ("Ask My Chat")
* **Problem**: Keyword search in existing messengers fails when the exact phrasing isn't remembered (e.g., searching for *"hotel booking"* when the sender wrote *"reserved a room"*).
* **Solution**: A natural language semantic query engine over conversation history.
* **Example Queries**:
  * *"Where did Henro say the meeting venue is?"*
  * *"Find the account number sent last month."*
  * *"What time did Pastor mention for the rehearsal?"*
* **Impact**: Eliminates endless scrolling through months of chat logs, saving users massive amounts of time.

---

## 3. 📄 In-Chat Document & PDF Intelligence
* **Problem**: Users frequently receive multi-page church bulletins, program schedules, legal contracts, or reports on mobile, but reading long PDFs on small screens is tedious.
* **Solution**: An inline **"✨ Summarize Document"** chip on document bubbles.
* **Features**:
  * Instant 4-bullet executive summary.
  * Quick-question bar (e.g., *"What is the main topic on page 2?"* or *"What is the total price quoted?"*).
* **Impact**: High-frequency utility for business, church leadership, and student groups.

---

## 4. 📅 Smart Event & Reminder Extractor
* **Problem**: Dates and commitments in chat messages frequently get buried and forgotten.
* **Solution**: On-device entity recognition that detects dates, times, and actionable commitments in text.
* **UI**: A subtle smart chip beneath the message:
  * **"📅 Add to Calendar: Saturday, 5:00 PM"**
* **1-Tap Action**: Opens the native calendar event creation pre-filled with details and a link back to the conversation.

---

## 5. ✍️ Message Ghostwriter & Tone Polisher
* **Problem**: Users on the move need to reply quickly or rephrase drafts to sound more professional, polite, or concise.
* **Solution**: An AI magic wand icon in the chat input bar offering 3 rapid one-tap adjustments:
  * **Polite & Professional**: Softens direct phrasing for formal or respectful communication.
  * **Concise**: Condenses wordy thoughts into crisp, clear sentences.
  * **Fix Grammar & Flow**: One-tap correction of spelling and punctuation without altering the user's voice.
  * **Instant Translation**: One-tap translation into French, Spanish, Yoruba, Swahili, etc.

---

## 6. 🎧 Deep AI Noise Cancellation on Calls
* **Problem**: Calls made in loud environments (markets, traffic, background music, or wind) suffer from poor audio intelligibility.
* **Solution**: A deep neural noise suppression filter integrated into the LiveKit WebRTC audio pipeline.
* **Impact**: Delivers crystal-clear voice clarity even in high-noise African urban environments, making LiChat calls distinctly higher quality than regular phone calls.

---

## 7. 🗣️ Voice Note AI Transcriber & TL;DR (Phase 1 Built ✅)
* **Problem**: Inability to listen to audio notes in public, work, or quiet settings.
* **Solution**: An inline **"✨ Transcribe"** chip that generates the full spoken transcript and a 1-sentence TL;DR summary right under the waveform.

---

## Implementation Matrix & Phasing

| Feature | Category | Effort | User Impact | Suggested Phase |
|---|---|---|---|---|
| **Voice Note Transcriber** | Audio | Completed ✅ | ⭐⭐⭐⭐⭐ | Phase 1 (Built) |
| **Smart Tone Polisher** | Text Input | Low | ⭐⭐⭐⭐ | Phase 2 |
| **Calendar/Reminder Extractor** | Productivity | Medium | ⭐⭐⭐⭐ | Phase 2 |
| **Document / PDF Summarizer** | Productivity | Medium | ⭐⭐⭐⭐⭐ | Phase 3 |
| **Post-Call AI Summary** | WebRTC / Audio | High | ⭐⭐⭐⭐⭐ | Phase 3 |
| **Semantic Memory Search** | Database / AI | High | ⭐⭐⭐⭐⭐ | Phase 4 |
| **Call Noise Suppression** | WebRTC Pipeline | Medium | ⭐⭐⭐⭐ | Phase 4 |

---

## Architecture Principles
1. **Zero Clutter (Hick's Law)**: AI features appear as progressive chips only when relevant—never as an intrusive barrier.
2. **Decoupled Service**: All AI logic routes through `lib/services/ai_service.dart`, allowing hot-swapping between Google Gemini API, cloud endpoints, and on-device models.
3. **Privacy First**: Voice audio and document texts processed ephemerally with zero permanent storage of raw tokens.
