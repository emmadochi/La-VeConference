// ==========================================
// LIVE POLLS & Q&A MODULE
// ==========================================
import { state } from "./state.js";
import { showToast } from "./utils.js";

export function broadcast(payload) {
    if (!state.currentRoom || state.currentRoom.state !== 'connected') return;
    const data = new TextEncoder().encode(JSON.stringify(payload));
    state.currentRoom.localParticipant.publishData(data, { reliable: true });
}

export function renderPollsUI() {
    const createSection = document.getElementById('pollCreateSection');
    const activeSection = document.getElementById('pollActiveSection');
    const emptyState = document.getElementById('pollEmptyState');
    if (!createSection || !activeSection || !emptyState) return;

    if (state.activePoll) {
        createSection.style.display = 'none';
        emptyState.style.display = 'none';
        activeSection.style.display = 'flex';
        activeSection.style.flexDirection = 'column';
        activeSection.style.gap = '10px';
        const questionEl = document.getElementById('activePollQuestion');
        if (questionEl) questionEl.textContent = state.activePoll.question;
        const endBtn = document.getElementById('endPollBtn');
        if (endBtn) endBtn.style.display = state.isAdmin ? 'block' : 'none';
        const totalVotes = Object.values(state.activePoll.votes || {}).reduce((s, v) => s + v, 0);
        const optionsDisplay = document.getElementById('pollOptionsDisplay');
        if (optionsDisplay) {
            optionsDisplay.innerHTML = '';
            state.activePoll.options.forEach((opt, idx) => {
                const votes = state.activePoll.votes[idx] || 0;
                const pct = totalVotes ? Math.round((votes / totalVotes) * 100) : 0;
                const btn = document.createElement('button');
                btn.className = 'poll-vote-btn' + (state.localVotedOption === idx ? ' voted-for' : '') + (state.localVotedOption !== null ? ' disabled' : '');
                btn.style.setProperty('--pct', pct + '%');
                const span1 = document.createElement('span'); span1.textContent = opt;
                const span2 = document.createElement('span');
                const strong = document.createElement('strong'); strong.textContent = pct + '%';
                const voteCount = document.createElement('span'); voteCount.className = 'poll-votes-count'; voteCount.textContent = ` (${votes})`;
                span2.appendChild(strong); span2.appendChild(voteCount);
                btn.appendChild(span1); btn.appendChild(span2);
                if (state.localVotedOption === null) { btn.addEventListener('click', () => castVote(idx)); }
                optionsDisplay.appendChild(btn);
            });
        }
        const resultsBar = document.getElementById('pollResultsBar');
        if (resultsBar) {
            resultsBar.innerHTML = `<p class="poll-total-votes">${totalVotes} vote${totalVotes !== 1 ? 's' : ''} total</p>`;
        }
    } else {
        activeSection.style.display = 'none';
        emptyState.style.display = 'flex';
        if (createSection) {
            createSection.style.display = state.isAdmin ? 'flex' : 'none';
            createSection.style.flexDirection = 'column';
        }
    }
}

export function castVote(optionIdx) {
    if (!state.currentRoom || state.localVotedOption !== null || !state.activePoll) return;
    state.localVotedOption = optionIdx;
    state.activePoll.votes[optionIdx] = (state.activePoll.votes[optionIdx] || 0) + 1;
    renderPollsUI();
    broadcast({ type: 'poll_vote', optionIdx });
}

export function handlePollLaunch(poll) {
    state.activePoll = { ...poll, votes: {} };
    poll.options.forEach((_, i) => { state.activePoll.votes[i] = 0; });
    state.localVotedOption = null;
    renderPollsUI();
    showToast('📊 New poll launched!');
    const qaBadge = document.getElementById('qaBadge');
    if (!state.isPollQaOpen && qaBadge) { qaBadge.style.display = 'block'; }
}

export function handlePollVoteUpdate(optionIdx) {
    if (!state.activePoll) return;
    state.activePoll.votes[optionIdx] = (state.activePoll.votes[optionIdx] || 0) + 1;
    renderPollsUI();
}

export function handlePollEnd() {
    if (!state.activePoll) return;
    showToast('📊 Poll ended.');
    state.activePoll = null;
    state.localVotedOption = null;
    renderPollsUI();
}

export function renderQaUI() {
    const list = document.getElementById('qaQuestionsList');
    const emptyState = document.getElementById('qaEmptyState');
    if (!list) return;
    list.querySelectorAll('.qa-question-card').forEach(c => c.remove());
    if (state.qaQuestions.length === 0) {
        if (emptyState) emptyState.style.display = 'flex';
        return;
    }
    if (emptyState) emptyState.style.display = 'none';
    const sorted = [...state.qaQuestions].sort((a, b) => {
        if (a.answered !== b.answered) return a.answered ? 1 : -1;
        return b.upvotes - a.upvotes;
    });
    sorted.forEach(q => {
        const card = document.createElement('div');
        card.className = 'qa-question-card';
        card.id = `qa-${q.id}`;
        const timeStr = new Date(q.ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        const hasVoted = state.localQaUpvoted.has(q.id);

        const meta = document.createElement('div'); meta.className = 'qa-question-meta';
        const author = document.createElement('span'); author.className = 'qa-question-author'; author.textContent = q.author;
        const time = document.createElement('span'); time.className = 'qa-question-time'; time.textContent = timeStr;
        meta.appendChild(author); meta.appendChild(time);

        const textEl = document.createElement('p'); textEl.className = 'qa-question-text'; textEl.textContent = q.text;

        const actions = document.createElement('div'); actions.className = 'qa-question-actions';
        const upvoteBtn = document.createElement('button');
        upvoteBtn.className = 'qa-upvote-btn' + (hasVoted ? ' voted' : '');
        upvoteBtn.textContent = `👍 ${q.upvotes}`;
        upvoteBtn.addEventListener('click', () => {
            if (state.localQaUpvoted.has(q.id)) return;
            state.localQaUpvoted.add(q.id);
            const qObj = state.qaQuestions.find(x => x.id === q.id);
            if (qObj) qObj.upvotes++;
            renderQaUI();
            broadcast({ type: 'qa_upvote', questionId: q.id });
        });
        actions.appendChild(upvoteBtn);

        if (q.answered) {
            const badge = document.createElement('span'); badge.className = 'qa-answered-badge'; badge.textContent = '✓ Answered';
            actions.appendChild(badge);
        } else if (state.isAdmin) {
            const ansBtn = document.createElement('button'); ansBtn.className = 'qa-answer-btn'; ansBtn.textContent = 'Mark Answered';
            ansBtn.addEventListener('click', () => { 
                handleQaAnswered(q.id); 
                broadcast({ type: 'qa_answered', questionId: q.id }); 
            });
            actions.appendChild(ansBtn);
        }

        card.appendChild(meta); card.appendChild(textEl); card.appendChild(actions);
        list.appendChild(card);
    });
    list.scrollTop = list.scrollHeight;
}

export function handleQaNewQuestion(question) {
    state.qaQuestions.push(question);
    renderQaUI();
    const qaBadge = document.getElementById('qaBadge');
    if (!state.isPollQaOpen) {
        state.newQaCount++;
        if (qaBadge) qaBadge.style.display = 'block';
        showToast(`❓ New question from ${question.author}`);
    }
}

export function handleQaUpvote(questionId) {
    const q = state.qaQuestions.find(x => x.id === questionId);
    if (q) { q.upvotes++; renderQaUI(); }
}

export function handleQaAnswered(questionId) {
    const q = state.qaQuestions.find(x => x.id === questionId);
    if (q) { q.answered = true; renderQaUI(); }
}

export function initPollsAndQaListeners() {
    const addPollOptionBtn = document.getElementById('addPollOptionBtn');
    if (addPollOptionBtn) {
        addPollOptionBtn.addEventListener('click', () => {
            const container = document.getElementById('pollOptionsContainer');
            const count = container.querySelectorAll('.poll-option-input').length + 1;
            if (count > 6) { showToast('Max 6 options allowed.', true); return; }
            const inp = document.createElement('input');
            inp.type = 'text'; inp.className = 'modal-input poll-option-input'; inp.placeholder = `Option ${count}`;
            container.appendChild(inp);
        });
    }

    const launchPollBtn = document.getElementById('launchPollBtn');
    if (launchPollBtn) {
        launchPollBtn.addEventListener('click', () => {
            if (!state.currentRoom || state.currentRoom.state !== 'connected') return;
            const question = document.getElementById('pollQuestionInput').value.trim();
            const optInputs = document.querySelectorAll('.poll-option-input');
            const options = Array.from(optInputs).map(i => i.value.trim()).filter(Boolean);
            if (!question) { showToast('Please enter a question.', true); return; }
            if (options.length < 2) { showToast('Please add at least 2 options.', true); return; }
            const poll = { question, options };
            handlePollLaunch(poll);
            broadcast({ type: 'poll_launch', poll });
            document.getElementById('pollQuestionInput').value = '';
            optInputs.forEach((inp, i) => { inp.value = ''; if (i >= 2) inp.remove(); });
        });
    }

    const endPollBtn = document.getElementById('endPollBtn');
    if (endPollBtn) {
        endPollBtn.addEventListener('click', () => { 
            handlePollEnd(); 
            broadcast({ type: 'poll_end' }); 
        });
    }

    const submitQaBtn = document.getElementById('submitQaBtn');
    const qaQuestionInput = document.getElementById('qaQuestionInput');
    if (submitQaBtn && qaQuestionInput) {
        submitQaBtn.addEventListener('click', () => {
            if (!state.currentRoom || state.currentRoom.state !== 'connected') return;
            const text = qaQuestionInput.value.trim();
            if (!text) return;
            const question = {
                id: Date.now().toString(36) + Math.random().toString(36).slice(2),
                author: state.userName, text, upvotes: 0, answered: false, ts: Date.now()
            };
            handleQaNewQuestion(question);
            broadcast({ type: 'qa_question', question });
            qaQuestionInput.value = '';
        });
        qaQuestionInput.addEventListener('keypress', (e) => { 
            if (e.key === 'Enter') submitQaBtn.click(); 
        });
    }
}
