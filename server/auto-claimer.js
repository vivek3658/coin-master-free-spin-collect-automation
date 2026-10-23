const { exec, execFile } = require('child_process');
const fs = require('fs');
const path = require('path');
const crawler = require('./crawler');

// Standard ADB search paths across platforms
const CANDIDATE_ADB_PATHS = [
  'adb',
  'C:\\Users\\vivek\\AppData\\Local\\Android\\Sdk\\platform-tools\\adb.exe',
  path.join(process.env.LOCALAPPDATA || '', 'Android', 'Sdk', 'platform-tools', 'adb.exe'),
  'C:\\Android\\platform-tools\\adb.exe',
  '/usr/bin/adb',
  '/usr/local/bin/adb',
  '/data/data/com.termux/files/usr/bin/adb',
];

class SmartphoneCmdAutoClaimer {
  constructor() {
    this.adbPath = this.resolveAdbPath();
    this.isRunning = false;
    this.isPaused = false;
    this.stopRequested = false;
    this.currentStep = 0;
    this.totalSteps = 0;
    this.currentReward = null;
    this.statusMessage = 'Idle';
    this.delaySeconds = 4;
    this.targetDeviceId = null;
    this.logs = [];
    this.isTermux = fs.existsSync('/data/data/com.termux');
  }

  resolveAdbPath() {
    for (const p of CANDIDATE_ADB_PATHS) {
      if (p === 'adb') continue;
      try {
        if (p && fs.existsSync(p)) return p;
      } catch (_) {}
    }
    return 'adb';
  }

  log(msg) {
    const timestamp = new Date().toLocaleTimeString();
    const entry = `[${timestamp}] ${msg}`;
    console.log(`[AutoClaimer] ${entry}`);
    this.logs.unshift(entry);
    if (this.logs.length > 60) this.logs.pop();
  }

  /**
   * Securely validates parameters to prevent command injection
   */
  sanitizeToken(str) {
    if (typeof str !== 'string') return '';
    return str.replace(/[^a-zA-Z0-9_\-\.\:\=]/g, '');
  }

  async runShellCommand(cmd) {
    return new Promise((resolve) => {
      exec(cmd, { timeout: 15000 }, (err, stdout, stderr) => {
        if (err) {
          return resolve({ success: false, output: (stderr || err.message).trim() });
        }
        resolve({ success: true, output: stdout.trim() });
      });
    });
  }

  /**
   * Checks connection to smartphone over USB or Wi-Fi ADB
   */
  async checkAdbConnection() {
    // If running inside Termux on Android, we have direct OS shell access
    if (this.isTermux) {
      return {
        connected: true,
        mode: 'termux-native',
        devices: ['localhost (Termux Native)'],
        activeDevice: 'localhost',
      };
    }

    const res = await this.runShellCommand(`"${this.adbPath}" devices`);
    if (!res.success) {
      return { connected: false, error: res.output, devices: [] };
    }

    const lines = res.output.split('\n').filter((l) => l.trim() && !l.includes('List of devices'));
    const devices = lines
      .filter((l) => l.includes('\tdevice'))
      .map((l) => l.split('\t')[0].trim());

    this.targetDeviceId = devices.length > 0 ? devices[0] : null;

    return {
      connected: devices.length > 0,
      mode: 'adb',
      devices: devices,
      activeDevice: this.targetDeviceId,
    };
  }

  /**
   * Connect to wireless ADB via IP:port
   */
  async connectWireless(ipPort) {
    const cleanIpPort = this.sanitizeToken(ipPort);
    if (!cleanIpPort || !cleanIpPort.includes(':')) {
      return { success: false, message: 'Invalid IP:Port format (e.g. 192.168.1.50:5555)' };
    }
    const res = await this.runShellCommand(`"${this.adbPath}" connect ${cleanIpPort}`);
    return {
      success: res.output.includes('connected') || res.output.includes('already connected'),
      output: res.output,
    };
  }

  /**
   * Starts sequential auto-collection of all unclaimed promo links
   * @param {number} delay Delay between claims (default 4 seconds)
   * @param {string|null} specificDevice Optional target device id
   */
  async startAutoClaim(delay = 4, specificDevice = null) {
    if (this.isRunning) {
      return { success: false, message: 'Auto-collector is already currently running.' };
    }

    const adbInfo = await this.checkAdbConnection();
    if (!adbInfo.connected && !this.isTermux) {
      this.log('❌ No Android smartphone detected via ADB. Connect via USB or Wireless ADB.');
      return {
        success: false,
        message: 'No Android phone detected. Please connect phone via USB (with USB Debugging enabled) or Wireless ADB.',
        connected: false,
      };
    }

    const deviceId = this.sanitizeToken(specificDevice || adbInfo.activeDevice);
    this.targetDeviceId = deviceId;
    this.delaySeconds = Math.max(2, Math.min(20, parseInt(delay, 10) || 4));

    // Gather unclaimed rewards
    const all = crawler.getCachedRewards();
    const claimedList = crawler.getClaimedRewards();
    const claimedSet = new Set(claimedList.map((c) => c.code.toLowerCase().trim()));
    const unclaimed = all.filter((r) => !claimedSet.has(r.code.toLowerCase().trim()));

    if (unclaimed.length === 0) {
      this.log('✓ All rewards are already collected! Nothing unclaimed.');
      return { success: true, message: 'All rewards have already been collected!', count: 0 };
    }

    this.isRunning = true;
    this.isPaused = false;
    this.stopRequested = false;
    this.totalSteps = unclaimed.length;
    this.currentStep = 0;
    this.statusMessage = `Starting auto-collect for ${unclaimed.length} rewards (${this.delaySeconds}s delay)...`;
    this.log(`🚀 Starting collection for ${unclaimed.length} unclaimed rewards on ${deviceId || 'device'} (${this.delaySeconds}s delay)`);

    // Launch Coin Master game to foreground first
    try {
      if (this.isTermux) {
        await this.runShellCommand('am start -n com.moonactive.coinmaster/com.moonactive.coinmaster.CoinMasterActivity');
      } else {
        await this.runShellCommand(
          `"${this.adbPath}" -s ${deviceId} shell monkey -p com.moonactive.coinmaster -c android.intent.category.LAUNCHER 1`
        );
      }
      this.log('📱 Bringing Coin Master to front. Initializing 3s warm-up...');
      await new Promise((r) => setTimeout(r, 3000));
    } catch (_) {}

    // Asynchronous background collection queue
    (async () => {
      try {
        for (let i = 0; i < unclaimed.length; i++) {
          if (this.stopRequested) {
            this.log('🛑 Collection HALTED immediately by user request.');
            this.statusMessage = 'Stopped by user';
            break;
          }

          while (this.isPaused && !this.stopRequested) {
            this.statusMessage = 'Paused';
            await new Promise((r) => setTimeout(r, 500));
          }

          if (this.stopRequested) break;

          const reward = unclaimed[i];
          const cleanCode = this.sanitizeToken(reward.code);
          this.currentStep = i + 1;
          this.currentReward = reward;
          this.statusMessage = `Collecting [${this.currentStep}/${this.totalSteps}]: ${reward.title}`;
          this.log(`[${this.currentStep}/${this.totalSteps}] Invoking intent for: ${reward.title} (${cleanCode})`);

          // Deliver deep-link promotion intent to Coin Master
          let intentCmd = '';
          if (this.isTermux) {
            intentCmd = `am start -a android.intent.action.VIEW -d "coinmaster://promotions?c=${cleanCode}"`;
          } else {
            intentCmd = `"${this.adbPath}" -s ${deviceId} shell am start -a android.intent.action.VIEW -d "coinmaster://promotions?c=${cleanCode}"`;
          }

          const intentRes = await this.runShellCommand(intentCmd);
          if (intentRes.success) {
            this.log(`✓ Intent dispatched to game: ${cleanCode}`);
          } else {
            this.log(`⚠ Intent warning: ${intentRes.output}`);
          }

          // Mark claimed in crawler cache
          crawler.markAsClaimed(cleanCode, 'claimed');

          // Wait configured delay in 1-second chunks for instant stop responsiveness
          for (let sec = 0; sec < this.delaySeconds; sec++) {
            if (this.stopRequested) break;
            await new Promise((r) => setTimeout(r, 1000));
          }
        }

        if (!this.stopRequested) {
          this.log('🎉 Collection completed! All unclaimed rewards processed.');
          this.statusMessage = 'Completed';
        }
      } catch (err) {
        this.log(`❌ Error in runner loop: ${err.message}`);
        this.statusMessage = `Error: ${err.message}`;
      } finally {
        this.isRunning = false;
        this.currentReward = null;
      }
    })();

    return {
      success: true,
      message: `Auto-collector initiated for ${unclaimed.length} rewards.`,
      total: unclaimed.length,
      delaySeconds: this.delaySeconds,
    };
  }

  /**
   * Immediate Emergency Stop
   */
  stop() {
    if (!this.isRunning) {
      return { success: false, message: 'Auto-collector is not currently active.' };
    }
    this.stopRequested = true;
    this.isRunning = false;
    this.statusMessage = 'Stopped by user';
    this.log('🛑 Emergency STOP triggered. Sequence aborted.');
    return { success: true, message: 'Collection sequence immediately halted.' };
  }

  pause() {
    this.isPaused = true;
    this.statusMessage = 'Paused';
    this.log('⏸ Collection paused.');
    return { success: true, message: 'Collector paused.' };
  }

  resume() {
    this.isPaused = false;
    this.statusMessage = 'Resuming';
    this.log('▶ Collection resumed.');
    return { success: true, message: 'Collector resumed.' };
  }

  getStatus() {
    return {
      isRunning: this.isRunning,
      isPaused: this.isPaused,
      currentStep: this.currentStep,
      totalSteps: this.totalSteps,
      currentReward: this.currentReward,
      statusMessage: this.statusMessage,
      delaySeconds: this.delaySeconds,
      targetDeviceId: this.targetDeviceId,
      logs: this.logs.slice(0, 15),
    };
  }
}

module.exports = new SmartphoneCmdAutoClaimer();
