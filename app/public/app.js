// State Management
let allRewards = [];
let activeFilter = 'all';
let searchQuery = '';
let selectedDelay = 4;
let isCollecting = false;
let collectionMode = 'web'; // 'adb' or 'web'
let localQueue = [];
let localStep = 0;
let localStopRequested = false;
let localIsPaused = false;
let statusPollInterval = null;

// DOM Elements
const rewardsGrid = document.getElementById('rewardsGrid');
const filteredCount = document.getElementById('filteredCount');
const unclaimedBadge = document.getElementById('unclaimedBadge');
const statTotal = document.getElementById('statTotal');
const statUnclaimed = document.getElementById('statUnclaimed');
const statClaimed = document.getElementById('statClaimed');
const statSyncTime = document.getElementById('statSyncTime');
const searchInput = document.getElementById('searchInput');
const filterPills = document.querySelectorAll('.pill');
const phoneStatusPill = document.getElementById('phoneStatusPill');
const phoneStatusText = document.getElementById('phoneStatusText');
const btnRefresh = document.getElementById('btnRefresh');

// Modal Elements
const preFlightModal = document.getElementById('preFlightModal');
const btnOpenCollectModal = document.getElementById('btnOpenCollectModal');
const btnCloseModal = document.getElementById('btnCloseModal');
const btnCancelModal = document.getElementById('btnCancelModal');
const btnConfirmAutoCollect = document.getElementById('btnConfirmAutoCollect');
const delaySlider = document.getElementById('delaySlider');
const delayDisplay = document.getElementById('delayDisplay');

// Floating Notification Bar Elements
const floatingCollectorBar = document.getElementById('floatingCollectorBar');
const collectorProgressFill = document.getElementById('collectorProgressFill');
const collectorStatusTag = document.getElementById('collectorStatusTag');
const collectorStepInfo = document.getElementById('collectorStepInfo');
const collectorDelayInfo = document.getElementById('collectorDelayInfo');
const collectorRewardName = document.getElementById('collectorRewardName');
const btnFloatingStop = document.getElementById('btnFloatingStop');
const btnFloatingPause = document.getElementById('btnFloatingPause');
const spinnerDisc = document.getElementById('spinnerDisc');

// Initialize
document.addEventListener('DOMContentLoaded', () => {
  requestNotificationPermission();
  fetchSpins();
  checkPhoneConnection();
  setupEventListeners();

  // Poll phone status every 15 seconds
  setInterval(checkPhoneConnection, 15000);
});

function setupEventListeners() {
  // Search input
  searchInput.addEventListener('input', (e) => {
    searchQuery = e.target.value.toLowerCase().trim();
    renderRewards();
  });

  // Filter pills
  filterPills.forEach((pill) => {
    pill.addEventListener('click', () => {
      filterPills.forEach((p) => p.classList.remove('active'));
      pill.classList.add('active');
      activeFilter = pill.dataset.filter;
      renderRewards();
    });
  });

  // Sync button
  btnRefresh.addEventListener('click', async () => {
    const icon = btnRefresh.querySelector('.spin-icon');
    icon.classList.add('spinning');
    try {
      const res = await fetch('/api/spins/refresh', { method: 'POST' });
      const data = await res.json();
      if (data.success) {
        allRewards = data.rewards;
        updateStats();
        renderRewards();
      }
    } catch (e) {
      console.warn('Sync failed:', e.message);
    } finally {
      setTimeout(() => icon.classList.remove('spinning'), 800);
    }
  });

  // Modal controls
  btnOpenCollectModal.addEventListener('click', () => {
    const unclaimed = allRewards.filter((r) => !r.isClaimed);
    if (unclaimed.length === 0) {
      showToast('All rewards have already been collected!');
      return;
    }
    preFlightModal.classList.add('open');
  });

  btnCloseModal.addEventListener('click', () => preFlightModal.classList.remove('open'));
  btnCancelModal.addEventListener('click', () => preFlightModal.classList.remove('open'));

  delaySlider.addEventListener('input', (e) => {
    selectedDelay = parseInt(e.target.value, 10);
    delayDisplay.textContent = `${selectedDelay} seconds`;
  });

  btnConfirmAutoCollect.addEventListener('click', () => {
    preFlightModal.classList.remove('open');
    startAutoCollect();
  });

  // Floating Bar Controls
  btnFloatingStop.addEventListener('click', () => {
    stopAutoCollect();
  });

  btnFloatingPause.addEventListener('click', () => {
    togglePause();
  });
}

// Fetch all compiled spins from Fastify server
async function fetchSpins() {
  try {
    const res = await fetch('/api/spins');
    if (res.status === 304) return; // Cache is up-to-date
    const data = await res.json();
    if (data.success) {
      allRewards = data.rewards;
      updateStats(data.lastCrawlTime);
      renderRewards();
    }
  } catch (err) {
    console.error('Failed to load spins:', err);
    filteredCount.textContent = 'Unable to connect to server';
  }
}

// Check smartphone ADB connection
async function checkPhoneConnection() {
  try {
    const res = await fetch('/api/adb/devices');
    const data = await res.json();

    if (data.connected && data.devices && data.devices.length > 0) {
      collectionMode = 'adb';
      phoneStatusPill.classList.add('online');
      phoneStatusText.textContent = `Phone: ${data.devices[0]}`;
      phoneStatusPill.title = 'Android Debug Bridge connected. Collect All uses direct smartphone shell commands!';
    } else {
      collectionMode = 'web';
      phoneStatusPill.classList.remove('online');
      const isMobile = /Android|iPhone|iPad/i.test(navigator.userAgent);
      phoneStatusText.textContent = isMobile ? 'Mobile Web Active' : 'No ADB (Web Mode)';
      phoneStatusPill.title = 'No USB ADB device. Collect All uses mobile browser deep links directly into Coin Master!';
    }
  } catch (_) {
    collectionMode = 'web';
  }
}

// Update stats ribbon
function updateStats(lastCrawlTime) {
  const total = allRewards.length;
  const claimed = allRewards.filter((r) => r.isClaimed).length;
  const unclaimed = total - claimed;

  statTotal.textContent = total;
  statUnclaimed.textContent = unclaimed;
  statClaimed.textContent = claimed;
  unclaimedBadge.textContent = unclaimed;

  if (lastCrawlTime) {
    const date = new Date(lastCrawlTime);
    statSyncTime.textContent = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  } else {
    statSyncTime.textContent = 'Active';
  }
}

// Render filtered reward cards
function renderRewards() {
  let filtered = allRewards.filter((r) => {
    // Tab filters
    if (activeFilter === 'unclaimed' && r.isClaimed) return false;
    if (activeFilter === 'claimed' && !r.isClaimed) return false;
    if (activeFilter === 'today' && r.dateCategory !== 'Today') return false;
    if (activeFilter === 'spins' && r.type !== 'spins') return false;
    if (activeFilter === 'coins' && r.type !== 'coins') return false;

    // Search query
    if (searchQuery) {
      const matchText = `${r.title} ${r.code} ${r.source} ${r.dateCategory}`.toLowerCase();
      if (!matchText.includes(searchQuery)) return false;
    }

    return true;
  });

  filteredCount.textContent = `${filtered.length} of ${allRewards.length} drops`;

  if (filtered.length === 0) {
    rewardsGrid.innerHTML = `
      <div style="grid-column: 1 / -1; text-align: center; padding: 3rem 1rem; color: var(--text-muted);">
        <p style="font-size: 1.1rem; font-weight: 600;">No matching reward drops found</p>
        <p style="font-size: 0.85rem; margin-top: 0.25rem;">Try clearing your filters or tap "Sync Drops" above.</p>
      </div>
    `;
    return;
  }

  rewardsGrid.innerHTML = filtered.map((r) => createRewardCardHtml(r)).join('');

  // Attach event handlers to card action buttons
  filtered.forEach((r) => {
    const toggleBtn = document.getElementById(`toggle_${r.code}`);
    if (toggleBtn) {
      toggleBtn.addEventListener('click', () => toggleRewardStatus(r.code, r.isClaimed));
    }
  });
}

function createRewardCardHtml(r) {
  const iconEmoji = r.type === 'coins' ? '💰' : r.type === 'mixed' ? '🎁' : '⚡';
  const cleanSource = r.source || 'Official Drop';
  const isClaimedClass = r.isClaimed ? 'claimed' : '';

  return `
    <div class="reward-card ${isClaimedClass}">
      <div class="card-top">
        <div class="card-badge-row">
          <span class="badge-source">${escapeHtml(cleanSource)}</span>
          <span class="badge-date">${escapeHtml(r.dateCategory || 'Today')}</span>
        </div>
        <span class="badge-status ${r.isClaimed ? 'claimed' : 'unclaimed'}">
          ${r.isClaimed ? 'Claimed' : 'Unclaimed'}
        </span>
      </div>

      <div class="card-main">
        <div class="reward-icon-box">${iconEmoji}</div>
        <div class="reward-details">
          <span class="reward-title">${escapeHtml(r.title)}</span>
          <span class="reward-code">${escapeHtml(r.code)}</span>
        </div>
      </div>

      <div class="card-actions">
        <a href="${r.appUrl}" class="action-game-link" title="Open directly in Coin Master app">
          <svg viewBox="0 0 24 24" fill="currentColor" style="width: 14px; height: 14px;">
            <polygon points="5 3 19 12 5 21 5 3"></polygon>
          </svg>
          <span>Claim in Game</span>
        </a>

        <a href="${r.webUrl}" target="_blank" rel="noopener" class="action-web-link" title="Open web redemption">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width: 14px; height: 14px;">
            <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path>
            <polyline points="15 3 21 3 21 9"></polyline>
            <line x1="10" y1="14" x2="21" y2="3"></line>
          </svg>
        </a>

        <button id="toggle_${escapeHtml(r.code)}" class="btn-toggle-claim" title="Toggle Claimed status">
          ${r.isClaimed ? 'Reset' : 'Done'}
        </button>
      </div>
    </div>
  `;
}

// Toggle claim status manually
async function toggleRewardStatus(code, currentStatus) {
  const endpoint = currentStatus ? `/api/spins/unclaim/${encodeURIComponent(code)}` : `/api/spins/claim/${encodeURIComponent(code)}`;
  try {
    const res = await fetch(endpoint, { method: 'POST' });
    const data = await res.json();
    if (data.success) {
      // Update local state
      const target = allRewards.find((r) => r.code === code);
      if (target) {
        target.isClaimed = !currentStatus;
      }
      updateStats();
      renderRewards();
    }
  } catch (e) {
    console.error('Toggle error:', e);
  }
}

// Master Auto-Collect Starter
async function startAutoCollect() {
  const unclaimed = allRewards.filter((r) => !r.isClaimed);
  if (unclaimed.length === 0) return;

  isCollecting = true;
  localStopRequested = false;
  localIsPaused = false;

  // Show bottom floating player bar
  floatingCollectorBar.classList.add('visible');
  collectorDelayInfo.textContent = `(${selectedDelay}s delay)`;

  if (collectionMode === 'adb') {
    // Mode A: Server ADB / Smartphone Shell Command Execution
    try {
      const res = await fetch('/api/auto-claim/start', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ delay: selectedDelay }),
      });
      const data = await res.json();
      if (!data.success) {
        showToast(data.message || 'ADB collection failed to start');
        stopAutoCollect();
        return;
      }

      // Start polling ADB collector status
      pollAdbStatus();
    } catch (err) {
      console.warn('ADB start failed, falling back to Web mode:', err.message);
      startBrowserIntentCollect(unclaimed);
    }
  } else {
    // Mode B: Direct Mobile Browser Sequential Queue
    startBrowserIntentCollect(unclaimed);
  }
}

// Poll server ADB auto-claim status
function pollAdbStatus() {
  if (statusPollInterval) clearInterval(statusPollInterval);

  statusPollInterval = setInterval(async () => {
    try {
      const res = await fetch('/api/auto-claim/status');
      const st = await res.json();

      if (!st.isRunning && isCollecting) {
        // Run completed or stopped
        clearInterval(statusPollInterval);
        isCollecting = false;
        fetchSpins(); // Refresh UI
        setTimeout(() => floatingCollectorBar.classList.remove('visible'), 2500);
        return;
      }

      if (st.isRunning) {
        updateFloatingBar(st.currentStep, st.totalSteps, st.currentReward?.title || 'Processing Reward');
      }
    } catch (_) {}
  }, 600);
}

// Mode B: Browser Sequential Intent Queue
async function startBrowserIntentCollect(unclaimed) {
  localQueue = unclaimed;
  localStep = 0;
  const total = localQueue.length;

  for (let i = 0; i < total; i++) {
    if (localStopRequested) break;

    while (localIsPaused && !localStopRequested) {
      await new Promise((r) => setTimeout(r, 400));
    }

    if (localStopRequested) break;

    localStep = i + 1;
    const reward = localQueue[i];

    updateFloatingBar(localStep, total, reward.title);

    // Send native OS notification
    sendOsNotification(`[${localStep}/${total}] Collecting: ${reward.title}`);

    // Dispatch intent deep link via hidden iframe to avoid leaving page or spawning tabs
    dispatchHiddenIntent(reward.appUrl);

    // Mark claimed on server
    try {
      await fetch(`/api/spins/claim/${encodeURIComponent(reward.code)}`, { method: 'POST' });
      reward.isClaimed = true;
      updateStats();
      renderRewards();
    } catch (_) {}

    // Wait configured delay
    for (let s = 0; s < selectedDelay; s++) {
      if (localStopRequested) break;
      await new Promise((r) => setTimeout(r, 1000));
    }
  }

  isCollecting = false;
  if (!localStopRequested) {
    collectorStatusTag.textContent = 'COMPLETE';
    showToast('🎉 All unclaimed drops have been collected!');
  }
  setTimeout(() => floatingCollectorBar.classList.remove('visible'), 3000);
}

// Dispatch deep link via hidden frame
function dispatchHiddenIntent(url) {
  let frame = document.getElementById('intentHiddenFrame');
  if (!frame) {
    frame = document.createElement('iframe');
    frame.id = 'intentHiddenFrame';
    frame.style.display = 'none';
    document.body.appendChild(frame);
  }
  frame.src = url;
}

// Update floating player notification bar
function updateFloatingBar(current, total, title) {
  const percent = Math.min(100, Math.round((current / total) * 100));
  collectorProgressFill.style.width = `${percent}%`;
  collectorStepInfo.textContent = `${current}/${total}`;
  collectorRewardName.textContent = title;
  collectorStatusTag.textContent = 'COLLECTING';
}

// Stop collection immediately
async function stopAutoCollect() {
  localStopRequested = true;
  isCollecting = false;

  if (statusPollInterval) {
    clearInterval(statusPollInterval);
    statusPollInterval = null;
  }

  collectorStatusTag.textContent = 'STOPPED';
  collectorRewardName.textContent = 'Collection halted by user.';
  collectorProgressFill.style.background = '#ef4444';

  try {
    await fetch('/api/auto-claim/stop', { method: 'POST' });
  } catch (_) {}

  fetchSpins();
  showToast('🛑 Auto-Collector stopped immediately.');

  setTimeout(() => {
    floatingCollectorBar.classList.remove('visible');
    collectorProgressFill.style.background = 'linear-gradient(90deg, #06b6d4, #10b981)';
  }, 2000);
}

// Toggle Pause / Resume
function togglePause() {
  localIsPaused = !localIsPaused;
  const pauseIcon = document.getElementById('pauseIcon');
  if (localIsPaused) {
    collectorStatusTag.textContent = 'PAUSED';
    pauseIcon.innerHTML = '<polygon points="5 3 19 12 5 21 5 3"></polygon>';
    fetch('/api/auto-claim/pause', { method: 'POST' }).catch(() => {});
  } else {
    collectorStatusTag.textContent = 'COLLECTING';
    pauseIcon.innerHTML = '<rect x="6" y="4" width="4" height="16"></rect><rect x="14" y="4" width="4" height="16"></rect>';
    fetch('/api/auto-claim/resume', { method: 'POST' }).catch(() => {});
  }
}

// Native Notification API
function requestNotificationPermission() {
  if ('Notification' in window && Notification.permission === 'default') {
    Notification.requestPermission();
  }
}

function sendOsNotification(body) {
  if ('Notification' in window && Notification.permission === 'granted') {
    try {
      new Notification('Coin Master Auto-Pilot', {
        body: body,
        icon: 'data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>⚡</text></svg>',
        silent: true,
      });
    } catch (_) {}
  }
}

function showToast(msg) {
  const toast = document.createElement('div');
  toast.style.position = 'fixed';
  toast.style.top = '1.5rem';
  toast.style.left = '50%';
  toast.style.transform = 'translateX(-50%)';
  toast.style.background = '#1e2230';
  toast.style.color = '#ffffff';
  toast.style.padding = '0.75rem 1.5rem';
  toast.style.borderRadius = '9999px';
  toast.style.fontSize = '0.85rem';
  toast.style.fontWeight = '700';
  toast.style.border = '1px solid rgba(255,255,255,0.15)';
  toast.style.boxShadow = '0 10px 30px rgba(0,0,0,0.5)';
  toast.style.zIndex = '9999';
  toast.textContent = msg;
  document.body.appendChild(toast);
  setTimeout(() => toast.remove(), 3000);
}

function escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}
