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

    // Wait for Firebase Auth to initialize
    fbFunctions.onAuthStateChanged(auth, async (user) => {
        if (user) {
            adminEmailSpan.textContent = user.email;
            
            try {
                const token = await user.getIdToken();
                await fetchStats(token);
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
