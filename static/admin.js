import { auth, fbFunctions } from './firebase-config.js';

document.addEventListener('DOMContentLoaded', () => {
    const errorBanner = document.getElementById('errorBanner');
    const loadingOverlay = document.getElementById('loadingOverlay');
    const adminEmailSpan = document.getElementById('adminEmail');
    const logoutBtn = document.getElementById('logoutBtn');
    
    // Stats Elements
    const statUsers = document.getElementById('statUsers');
    const statRooms = document.getElementById('statRooms');
    const statMeetings = document.getElementById('statMeetings');

    function showError(msg) {
        errorBanner.textContent = msg;
        errorBanner.style.display = 'block';
        loadingOverlay.style.display = 'none';
    }

    async function fetchStats(token) {
        try {
            const response = await fetch('/api/admin/stats', {
                method: 'GET',
                headers: {
                    'Authorization': `Bearer ${token}`
                }
            });
            
            if (!response.ok) {
                if (response.status === 403 || response.status === 401) {
                    throw new Error("You do not have admin privileges.");
                }
                throw new Error("Failed to load statistics.");
            }
            
            const data = await response.json();
            
            // Animate counting up for effect
            statUsers.textContent = data.total_users || 0;
            statRooms.textContent = data.active_rooms || 0;
            statMeetings.textContent = data.total_meetings || 0;

            // Render Chart
            renderChart(data);

            // Render Tables
            renderRecentUsers(data.users || []);
            renderUpcomingMeetings(data.meetings || []);
            
            loadingOverlay.style.display = 'none';
        } catch (e) {
            showError(e.message);
        }
    }

    function renderChart(data) {
        const ctx = document.getElementById('overviewChart').getContext('2d');
        // Destroy existing chart if re-rendering
        if(window.adminChart) {
            window.adminChart.destroy();
        }

        window.adminChart = new Chart(ctx, {
            type: 'bar',
            data: {
                labels: ['Total Users', 'Active Rooms', 'Scheduled Meetings'],
                datasets: [{
                    label: 'Platform Metrics',
                    data: [data.total_users, data.active_rooms, data.total_meetings],
                    backgroundColor: [
                        'rgba(0, 229, 255, 0.5)',
                        'rgba(255, 85, 85, 0.5)',
                        'rgba(155, 85, 255, 0.5)'
                    ],
                    borderColor: [
                        '#00e5ff',
                        '#ff5555',
                        '#9b55ff'
                    ],
                    borderWidth: 1,
                    borderRadius: 4
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        grid: {
                            color: 'rgba(255, 255, 255, 0.05)'
                        },
                        ticks: { color: '#8b949e' }
                    },
                    x: {
                        grid: { display: false },
                        ticks: { color: '#8b949e' }
                    }
                },
                plugins: {
                    legend: { display: false }
                }
            }
        });
    }

    function renderRecentUsers(users) {
        const tbody = document.getElementById('recentUsersTableBody');
        tbody.innerHTML = '';
        
        // Show up to 5 users
        const recent = users.slice(0, 5);
        if (recent.length === 0) {
            tbody.innerHTML = '<tr><td colspan="2" style="text-align: center; color: #8b949e;">No users found.</td></tr>';
            return;
        }

        recent.forEach(user => {
            const tr = document.createElement('tr');
            const nameCol = document.createElement('td');
            nameCol.innerHTML = `<strong>${user.displayName || 'User'}</strong><br><span style="font-size: 0.8rem; color: #8b949e;">${user.email}</span>`;
            
            const statusCol = document.createElement('td');
            const statusSpan = document.createElement('span');
            if (user.active_room) {
                statusSpan.className = 'badge-active';
                statusSpan.textContent = 'In Call';
            } else {
                statusSpan.className = 'badge-inactive';
                statusSpan.textContent = 'Offline';
            }
            statusCol.appendChild(statusSpan);

            tr.appendChild(nameCol);
            tr.appendChild(statusCol);
            tbody.appendChild(tr);
        });
    }

    function renderUpcomingMeetings(meetings) {
        const tbody = document.getElementById('upcomingMeetingsTableBody');
        tbody.innerHTML = '';
        
        // Show up to 5 meetings
        const upcoming = meetings.slice(0, 5);
        if (upcoming.length === 0) {
            tbody.innerHTML = '<tr><td colspan="2" style="text-align: center; color: #8b949e;">No meetings scheduled.</td></tr>';
            return;
        }

        upcoming.forEach(meet => {
            const tr = document.createElement('tr');
            const titleCol = document.createElement('td');
            titleCol.textContent = meet.title;
            
            const dateCol = document.createElement('td');
            if (meet.scheduled_time) {
                try {
                    const dt = new Date(meet.scheduled_time);
                    dateCol.textContent = dt.toLocaleString();
                } catch(e) {
                    dateCol.textContent = meet.scheduled_time;
                }
            } else {
                dateCol.textContent = 'Not specified';
            }

            tr.appendChild(titleCol);
            tr.appendChild(dateCol);
            tbody.appendChild(tr);
        });
    }

    // Navigation Tabs
    const navOverview = document.getElementById('navOverview');
    const navCampaigns = document.getElementById('navCampaigns');
    const navHelpdesk = document.getElementById('navHelpdesk');
    const openTicketsBadge = document.getElementById('openTicketsBadge');

    const overviewSection = document.getElementById('overviewSection');
    const campaignsSection = document.getElementById('campaignsSection');
    const helpdeskSection = document.getElementById('helpdeskSection');
    const viewTitle = document.getElementById('viewTitle');
    const successBanner = document.getElementById('successBanner');

    function switchTab(tab) {
        navOverview.classList.remove('active');
        navCampaigns.classList.remove('active');
        navHelpdesk.classList.remove('active');
        overviewSection.style.display = 'none';
        campaignsSection.style.display = 'none';
        helpdeskSection.style.display = 'none';

        if (tab === 'overview') {
            navOverview.classList.add('active');
            overviewSection.style.display = 'block';
            viewTitle.textContent = 'Dashboard Overview';
        } else if (tab === 'campaigns') {
            navCampaigns.classList.add('active');
            campaignsSection.style.display = 'block';
            viewTitle.textContent = 'Marketing Broadcasts & Email Engine';
            updateAudienceEstimate();
            fetchCampaignHistory();
        } else if (tab === 'helpdesk') {
            navHelpdesk.classList.add('active');
            helpdeskSection.style.display = 'block';
            viewTitle.textContent = 'Support Helpdesk & User Inquiries';
            fetchHelpdeskTickets();
        }
    }

    navOverview.addEventListener('click', () => switchTab('overview'));
    navCampaigns.addEventListener('click', () => switchTab('campaigns'));
    navHelpdesk.addEventListener('click', () => switchTab('helpdesk'));

    // Toggle Preview Tab
    tabPrevPush.addEventListener('click', () => {
        tabPrevPush.style.background = 'rgba(0, 229, 255, 0.2)';
        tabPrevPush.style.color = '#00e5ff';
        tabPrevPush.style.borderColor = '#00e5ff';
        tabPrevEmail.style.background = 'rgba(255, 255, 255, 0.05)';
        tabPrevEmail.style.color = '#8b949e';
        tabPrevEmail.style.borderColor = 'rgba(255, 255, 255, 0.1)';
        prevPushBox.style.display = 'block';
        prevEmailBox.style.display = 'none';
    });

    tabPrevEmail.addEventListener('click', () => {
        tabPrevEmail.style.background = 'rgba(0, 229, 255, 0.2)';
        tabPrevEmail.style.color = '#00e5ff';
        tabPrevEmail.style.borderColor = '#00e5ff';
        tabPrevPush.style.background = 'rgba(255, 255, 255, 0.05)';
        tabPrevPush.style.color = '#8b949e';
        tabPrevPush.style.borderColor = 'rgba(255, 255, 255, 0.1)';
        prevPushBox.style.display = 'none';
        prevEmailBox.style.display = 'block';
    });

    // Live preview update
    function updatePreview() {
        const titleVal = campTitle.value.trim() || 'Notification Title';
        const bodyVal = campBody.value.trim() || 'Your notification message will appear here for recipients.';
        const emailSubVal = campEmailSubject.value.trim() || titleVal;

        // Push Preview
        previewTitle.textContent = titleVal;
        previewBody.textContent = bodyVal;
        
        const actionType = campActionType.value;
        const actionVal = campActionValue.value.trim();
        if (actionType === 'open_room') {
            previewActionBadge.textContent = `🎥 Join Room: ${actionVal || 'Main Stage'}`;
            prevEmailBtn.textContent = `Join Meeting Stage →`;
        } else if (actionType === 'open_upgrade') {
            previewActionBadge.textContent = `💎 Unlock Pro Plan`;
            prevEmailBtn.textContent = `Unlock Pro Plan →`;
        } else if (actionType === 'open_notes') {
            previewActionBadge.textContent = `📝 View Meeting Notes`;
            prevEmailBtn.textContent = `View Meeting Notes →`;
        } else {
            previewActionBadge.textContent = `📢 Announcement`;
            prevEmailBtn.textContent = `Open La-Vie →`;
        }

        // Email Preview
        prevEmailSubject.innerHTML = `Subject: <span style="color: #00e5ff;">${emailSubVal}</span>`;
        prevEmailHeadline.textContent = titleVal;
        prevEmailBody.textContent = bodyVal;
    }

    campTitle.addEventListener('input', updatePreview);
    campEmailSubject.addEventListener('input', updatePreview);
    campBody.addEventListener('input', updatePreview);
    campActionType.addEventListener('change', updatePreview);
    campActionValue.addEventListener('input', updatePreview);

    // Audience estimate
    async function updateAudienceEstimate() {
        if (!currentToken) return;
        audienceBadge.textContent = 'Calculating...';
        try {
            const res = await fetch('/api/admin/audience-estimate', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${currentToken}`
                },
                body: JSON.stringify({ segment: campSegment.value })
            });
            if (res.ok) {
                const data = await res.json();
                audienceBadge.textContent = `🎯 ${data.count} Users (${data.token_count} Pushes & ${data.email_count || 0} Emails)`;
            }
        } catch (e) {
            audienceBadge.textContent = 'Audience: Ready';
        }
    }

    campSegment.addEventListener('change', updateAudienceEstimate);

    // Fetch past campaigns
    async function fetchCampaignHistory() {
        if (!currentToken) return;
        try {
            const res = await fetch('/api/admin/campaigns', {
                method: 'GET',
                headers: { 'Authorization': `Bearer ${currentToken}` }
            });
            if (res.ok) {
                const data = await res.json();
                renderCampaignHistory(data.campaigns || []);
            }
        } catch (e) {
            console.error('Error fetching campaign history:', e);
        }
    }

    function renderCampaignHistory(campaigns) {
        campaignHistoryTableBody.innerHTML = '';
        if (campaigns.length === 0) {
            campaignHistoryTableBody.innerHTML = '<tr><td colspan="6" style="text-align: center; color: #8b949e;">No past campaigns found.</td></tr>';
            return;
        }

        campaigns.forEach(c => {
            const tr = document.createElement('tr');
            
            const titleTd = document.createElement('td');
            titleTd.innerHTML = `<strong>${c.title || 'Untitled'}</strong><br><span style="font-size: 0.8rem; color: #8b949e;">${c.body ? (c.body.substring(0, 45) + '...') : ''}</span>`;
            
            const segmentTd = document.createElement('td');
            segmentTd.innerHTML = `<span class="badge-active" style="text-transform: capitalize;">${c.segment || 'All'}</span>`;
            
            const recipTd = document.createElement('td');
            recipTd.textContent = `${c.totalRecipients || 0} Users`;
            
            const pushTd = document.createElement('td');
            pushTd.innerHTML = `<span style="color: #00e5ff; font-weight: bold;">${c.devicePushSuccess || 0} sent</span>`;
            
            const emailTd = document.createElement('td');
            emailTd.innerHTML = `<span style="color: #58a6ff; font-weight: bold;">${c.emailSuccess || 0} sent</span>`;

            const dateTd = document.createElement('td');
            dateTd.textContent = c.sentAt ? new Date(c.sentAt).toLocaleString() : 'N/A';

            tr.appendChild(titleTd);
            tr.appendChild(segmentTd);
            tr.appendChild(recipTd);
            tr.appendChild(pushTd);
            tr.appendChild(emailTd);
            tr.appendChild(dateTd);
            campaignHistoryTableBody.appendChild(tr);
        });
    }

    // Handle broadcast campaign submission
    broadcastForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (!currentToken) return;

        const channels = [];
        if (chanPush.checked) channels.push('push');
        if (chanEmail.checked) channels.push('email');

        if (channels.length === 0) {
            alert('Please select at least one delivery channel (Push Notification or Email).');
            return;
        }

        const confirmSend = confirm(`Broadcast this campaign via [${channels.join(' & ').toUpperCase()}] to "${campSegment.options[campSegment.selectedIndex].text}"?`);
        if (!confirmSend) return;

        sendCampaignBtn.disabled = true;
        sendCampaignBtn.innerHTML = `<span class="spinner" style="width: 18px; height: 18px; border-width: 2px;"></span> Dispathing Multi-Channel Campaign...`;

        try {
            const res = await fetch('/api/admin/notifications/broadcast', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${currentToken}`
                },
                body: JSON.stringify({
                    title: campTitle.value.trim(),
                    email_subject: campEmailSubject.value.trim(),
                    body: campBody.value.trim(),
                    segment: campSegment.value,
                    channels: channels,
                    action_type: campActionType.value,
                    action_value: campActionValue.value.trim(),
                    image_url: campImageUrl.value.trim()
                })
            });

            const data = await res.json();
            if (!res.ok) {
                throw new Error(data.detail || 'Failed to dispatch campaign');
            }

            showSuccess(`🎉 Campaign broadcast completed! Reached ${data.recipients_count} users (${data.pushes_sent} mobile pushes, ${data.emails_sent} HTML emails).`);
            
            // Reset form
            campTitle.value = '';
            campEmailSubject.value = '';
            campBody.value = '';
            campActionValue.value = '';
            campImageUrl.value = '';
            updatePreview();
            fetchCampaignHistory();
        } catch (err) {
            showError(`Error sending broadcast: ${err.message}`);
        } finally {
            sendCampaignBtn.disabled = false;
            sendCampaignBtn.innerHTML = `<span class="material-symbols-outlined">rocket_launch</span> Send Broadcast Campaign`;
        }
    });

    // =========================================================================
    // HELPDESK & SUPPORT TICKET MANAGEMENT
    // =========================================================================
    const hdStatOpen = document.getElementById('hdStatOpen');
    const hdStatInProgress = document.getElementById('hdStatInProgress');
    const hdStatResolved = document.getElementById('hdStatResolved');
    const hdStatTotal = document.getElementById('hdStatTotal');

    const hdSearchInput = document.getElementById('hdSearchInput');
    const hdTicketList = document.getElementById('hdTicketList');
    const hdFilterBtns = document.querySelectorAll('.hd-filter-btn');

    const hdEmptyState = document.getElementById('hdEmptyState');
    const hdActiveContent = document.getElementById('hdActiveContent');
    const hdDetailTicketId = document.getElementById('hdDetailTicketId');
    const hdDetailCategory = document.getElementById('hdDetailCategory');
    const hdDetailPriority = document.getElementById('hdDetailPriority');
    const hdDetailSubject = document.getElementById('hdDetailSubject');
    const hdDetailUserName = document.getElementById('hdDetailUserName');
    const hdDetailUserEmail = document.getElementById('hdDetailUserEmail');
    const hdDetailDate = document.getElementById('hdDetailDate');
    const hdStatusSelect = document.getElementById('hdStatusSelect');
    const hdConversationThread = document.getElementById('hdConversationThread');

    const hdCannedSelect = document.getElementById('hdCannedSelect');
    const hdReplyForm = document.getElementById('hdReplyForm');
    const hdReplyMessage = document.getElementById('hdReplyMessage');
    const hdResolveOnReply = document.getElementById('hdResolveOnReply');
    const hdSendReplyBtn = document.getElementById('hdSendReplyBtn');

    let allTickets = [];
    let currentFilter = 'all';
    let selectedTicket = null;

    const CANNED_RESPONSES = {
        mic_cam_perm: `Hello!\n\nTo resolve camera and microphone permissions:\n1. On Chrome/Web: Tap the Lock/Settings icon next to the URL address bar -> Set Camera & Microphone to 'Allow' -> Reload the page.\n2. On Android/App: Go to device Settings -> Apps -> La-Vie Conference -> Permissions -> Allow Camera & Microphone.\n\nPlease let us know if you can join the room afterwards!`,
        stream_setup: `Hello!\n\nTo connect OBS or vMix to La-Vie:\n1. Open your Room settings on the Dashboard and click 'Multi-Streaming / Ingress'.\n2. Copy your RTMP Server URL and Stream Key.\n3. Paste them into OBS (Settings -> Stream -> Custom Service) or vMix (Streaming Settings).\n4. Click 'Start Streaming' in OBS/vMix, and your feed will immediately appear on the Main Stage.`,
        upgrade_plan: `Hello!\n\nThank you for reaching out regarding our subscription tiers! Our Ministry & Pro plans include multi-destination streaming (YouTube, Facebook, RTMP), unlimited participants, and high-bitrate recording. You can activate or upgrade directly from the subscription modal in your dashboard.`,
        resolved_msg: `Hello!\n\nWe are glad we could help resolve this for you! If you ever need further assistance for your live broadcasts or meetings, please don't hesitate to reach out again.\n\nHave a blessed time on La-Vie!`
    };

    // Filter Buttons
    hdFilterBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            hdFilterBtns.forEach(b => {
                b.classList.remove('active');
                b.style.background = 'rgba(255, 255, 255, 0.05)';
                b.style.color = '#8b949e';
                b.style.borderColor = 'rgba(255, 255, 255, 0.1)';
            });
            btn.classList.add('active');
            btn.style.background = 'rgba(0, 229, 255, 0.2)';
            btn.style.color = '#00e5ff';
            btn.style.borderColor = '#00e5ff';
            currentFilter = btn.getAttribute('data-filter');
            applyTicketFilters();
        });
    });

    hdSearchInput.addEventListener('input', applyTicketFilters);

    // Canned Response Selector
    hdCannedSelect.addEventListener('change', () => {
        const key = hdCannedSelect.value;
        if (key && CANNED_RESPONSES[key]) {
            hdReplyMessage.value = CANNED_RESPONSES[key];
            if (key === 'resolved_msg') {
                hdResolveOnReply.checked = true;
            }
        }
    });

    async function fetchHelpdeskTickets() {
        if (!currentToken) return;
        try {
            const res = await fetch('/api/admin/support/tickets', {
                headers: { 'Authorization': `Bearer ${currentToken}` }
            });
            if (res.ok) {
                const data = await res.json();
                allTickets = data.tickets || [];
                
                // Update metrics
                const stats = data.stats || {};
                hdStatOpen.textContent = stats.open || 0;
                hdStatInProgress.textContent = stats.in_progress || 0;
                hdStatResolved.textContent = stats.resolved || 0;
                hdStatTotal.textContent = stats.total || 0;

                // Update badge in sidebar
                if (stats.open > 0) {
                    openTicketsBadge.textContent = stats.open;
                    openTicketsBadge.style.display = 'inline-block';
                } else {
                    openTicketsBadge.style.display = 'none';
                }

                applyTicketFilters();

                // If a ticket was previously selected, refresh its view
                if (selectedTicket) {
                    const refreshed = allTickets.find(t => t.id === selectedTicket.id);
                    if (refreshed) {
                        selectTicket(refreshed);
                    }
                }
            }
        } catch (e) {
            console.error('Error fetching support tickets:', e);
        }
    }

    function applyTicketFilters() {
        const query = hdSearchInput.value.toLowerCase().trim();
        let filtered = allTickets;

        if (currentFilter !== 'all') {
            filtered = filtered.filter(t => (t.status || 'open').toLowerCase() === currentFilter);
        }

        if (query) {
            filtered = filtered.filter(t => 
                (t.subject && t.subject.toLowerCase().includes(query)) ||
                (t.ticketId && t.ticketId.toLowerCase().includes(query)) ||
                (t.userEmail && t.userEmail.toLowerCase().includes(query)) ||
                (t.userName && t.userName.toLowerCase().includes(query)) ||
                (t.message && t.message.toLowerCase().includes(query))
            );
        }

        renderTicketList(filtered);
    }

    function renderTicketList(tickets) {
        hdTicketList.innerHTML = '';
        if (tickets.length === 0) {
            hdTicketList.innerHTML = '<div style="text-align: center; color: #8b949e; padding: 30px 0;">No matching tickets found.</div>';
            return;
        }

        tickets.forEach(t => {
            const card = document.createElement('div');
            const isSelected = selectedTicket && selectedTicket.id === t.id;
            
            const st = (t.status || 'open').toLowerCase();
            let statusPill = `<span style="background: rgba(255, 170, 0, 0.15); color: #ffaa00; font-size: 0.7rem; font-weight: bold; padding: 2px 8px; border-radius: 6px;">🟡 Open</span>`;
            if (st === 'in_progress') {
                statusPill = `<span style="background: rgba(0, 229, 255, 0.15); color: #00e5ff; font-size: 0.7rem; font-weight: bold; padding: 2px 8px; border-radius: 6px;">🔵 In Progress</span>`;
            } else if (st === 'resolved') {
                statusPill = `<span style="background: rgba(0, 255, 163, 0.15); color: #00ffa3; font-size: 0.7rem; font-weight: bold; padding: 2px 8px; border-radius: 6px;">🟢 Resolved</span>`;
            }

            const priorityColor = t.priority === 'urgent' || t.priority === 'high' ? '#ff5555' : '#8b949e';

            card.style.cssText = `
                background: ${isSelected ? 'rgba(0, 229, 255, 0.1)' : 'rgba(255, 255, 255, 0.03)'};
                border: 1px solid ${isSelected ? '#00e5ff' : 'rgba(255, 255, 255, 0.08)'};
                border-radius: 10px;
                padding: 12px 14px;
                cursor: pointer;
                transition: all 0.2s ease;
            `;

            card.innerHTML = `
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
                    <span style="color: #00e5ff; font-weight: 700; font-size: 0.82rem; font-family: monospace;">#${t.ticketId || t.id}</span>
                    ${statusPill}
                </div>
                <div style="color: white; font-weight: 600; font-size: 0.9rem; margin-bottom: 4px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                    ${t.subject || 'No Subject'}
                </div>
                <div style="font-size: 0.78rem; color: #8b949e; margin-bottom: 6px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                    ${t.userName || t.userEmail || 'Unknown User'} &bull; <span style="color: ${priorityColor}; text-transform: capitalize;">${t.priority || 'Normal'}</span>
                </div>
                <div style="font-size: 0.72rem; color: #484f58; text-align: right;">
                    ${t.createdAt ? new Date(t.createdAt).toLocaleDateString() : ''}
                </div>
            `;

            card.addEventListener('click', () => {
                selectedTicket = t;
                selectTicket(t);
                applyTicketFilters();
            });

            hdTicketList.appendChild(card);
        });
    }

    function selectTicket(t) {
        selectedTicket = t;
        hdEmptyState.style.display = 'none';
        hdActiveContent.style.display = 'flex';

        hdDetailTicketId.textContent = `#${t.ticketId || t.id}`;
        hdDetailCategory.textContent = (t.category || 'General').replace('_', ' ');
        hdDetailPriority.textContent = (t.priority || 'Normal').toUpperCase();
        hdDetailPriority.style.color = t.priority === 'urgent' || t.priority === 'high' ? '#ff5555' : '#00e5ff';
        hdDetailSubject.textContent = t.subject || 'No Subject';
        hdDetailUserName.textContent = t.userName || 'User';
        hdDetailUserEmail.textContent = t.userEmail || 'No Email';
        hdDetailDate.textContent = t.createdAt ? new Date(t.createdAt).toLocaleString() : 'N/A';
        hdStatusSelect.value = (t.status || 'open').toLowerCase();

        // Render Conversation Thread
        hdConversationThread.innerHTML = '';

        // 1. Initial User Inquiry
        const userMsg = document.createElement('div');
        userMsg.style.cssText = `
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 12px;
            padding: 14px 16px;
        `;
        userMsg.innerHTML = `
            <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 8px;">
                <span class="material-symbols-outlined" style="font-size: 18px; color: #00e5ff;">person</span>
                <strong style="color: white; font-size: 0.88rem;">${t.userName || 'User'}</strong>
                <span style="font-size: 0.75rem; color: #8b949e; margin-left: auto;">${t.createdAt ? new Date(t.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : ''}</span>
            </div>
            <div style="color: #c9d1d9; font-size: 0.88rem; line-height: 1.5; white-space: pre-wrap;">${t.message || ''}</div>
        `;
        hdConversationThread.appendChild(userMsg);

        // 2. Admin & User Replies
        const replies = t.replies || [];
        replies.forEach(r => {
            const rDiv = document.createElement('div');
            const isAdmin = r.sender === 'admin';
            
            rDiv.style.cssText = `
                background: ${isAdmin ? 'rgba(0, 229, 255, 0.08)' : 'rgba(255, 255, 255, 0.05)'};
                border: 1px solid ${isAdmin ? 'rgba(0, 229, 255, 0.3)' : 'rgba(255, 255, 255, 0.1)'};
                border-left: 4px solid ${isAdmin ? '#00e5ff' : '#8b949e'};
                border-radius: 12px;
                padding: 14px 16px;
                margin-left: ${isAdmin ? '20px' : '0'};
            `;

            rDiv.innerHTML = `
                <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 8px;">
                    <span class="material-symbols-outlined" style="font-size: 18px; color: ${isAdmin ? '#00e5ff' : '#8b949e'};">${isAdmin ? 'support_agent' : 'person'}</span>
                    <strong style="color: ${isAdmin ? '#00e5ff' : 'white'}; font-size: 0.88rem;">${r.senderName || (isAdmin ? 'La-Vie Helpdesk' : 'User')}</strong>
                    <span style="font-size: 0.75rem; color: #8b949e; margin-left: auto;">${r.sentAt ? new Date(r.sentAt).toLocaleString([], { dateStyle: 'short', timeStyle: 'short' }) : ''}</span>
                </div>
                <div style="color: #ffffff; font-size: 0.88rem; line-height: 1.5; white-space: pre-wrap;">${r.message || ''}</div>
            `;
            hdConversationThread.appendChild(rDiv);
        });

        // Scroll to bottom of conversation
        hdConversationThread.scrollTop = hdConversationThread.scrollHeight;
    }

    // Status Selector Change
    hdStatusSelect.addEventListener('change', async () => {
        if (!selectedTicket || !currentToken) return;
        const newStatus = hdStatusSelect.value;
        try {
            const res = await fetch(`/api/admin/support/tickets/${selectedTicket.ticketId || selectedTicket.id}/status`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${currentToken}`
                },
                body: JSON.stringify({ status: newStatus })
            });
            if (res.ok) {
                showSuccess(`Ticket #${selectedTicket.ticketId} marked as ${newStatus.toUpperCase()}`);
                selectedTicket.status = newStatus;
                fetchHelpdeskTickets();
            }
        } catch (e) {
            showError('Failed to update ticket status');
        }
    });

    // Reply Form Submission
    hdReplyForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (!selectedTicket || !currentToken) return;

        const replyMsg = hdReplyMessage.value.trim();
        if (!replyMsg) return;

        hdSendReplyBtn.disabled = true;
        hdSendReplyBtn.innerHTML = `<span class="spinner" style="width: 16px; height: 16px; border-width: 2px;"></span> Sending...`;

        const newStatus = hdResolveOnReply.checked ? 'resolved' : 'in_progress';

        try {
            const res = await fetch(`/api/admin/support/tickets/${selectedTicket.ticketId || selectedTicket.id}/reply`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${currentToken}`
                },
                body: JSON.stringify({
                    message: replyMsg,
                    status: newStatus,
                    agent_name: 'La-Vie Support Team'
                })
            });

            const data = await res.json();
            if (!res.ok) {
                throw new Error(data.detail || 'Failed to dispatch reply');
            }

            showSuccess(`🎉 Reply sent! User received branded HTML email & in-app alert.`);
            hdReplyMessage.value = '';
            hdCannedSelect.value = '';
            
            await fetchHelpdeskTickets();
        } catch (err) {
            showError(`Error sending reply: ${err.message}`);
        } finally {
            hdSendReplyBtn.disabled = false;
            hdSendReplyBtn.innerHTML = `<span class="material-symbols-outlined" style="font-size: 18px;">send</span> Dispatch Reply &amp; Email`;
        }
    });

    // Wait for Firebase Auth to initialize
    fbFunctions.onAuthStateChanged(auth, async (user) => {
        if (user) {
            adminEmailSpan.textContent = user.email;
            
            try {
                currentToken = await user.getIdToken();
                await fetchStats(currentToken);
                await fetchHelpdeskTickets();
            } catch (e) {
                showError("Failed to authenticate with server.");
            }
        } else {
            // Not logged in, redirect to main page
            window.location.href = '/';
        }
    });

    logoutBtn.addEventListener('click', async () => {
        await fbFunctions.signOut(auth);
        window.location.href = '/';
    });
});
