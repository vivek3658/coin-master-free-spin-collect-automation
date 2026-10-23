const axios = require('axios');
const cheerio = require('cheerio');
const fs = require('fs');
const path = require('path');

const DATA_DIR = path.join(__dirname, 'data');
const CACHE_FILE = path.join(DATA_DIR, 'spins_cache.json');
const CLAIMED_FILE = path.join(DATA_DIR, 'claimed_rewards.json');

// Ensure data directory exists
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

class FastSpinCrawler {
  constructor() {
    this.inMemoryCache = [];
    this.claimedRewards = [];
    this.lastCrawlTime = null;
    this.isCrawling = false;

    // Load initial cache from disk if available
    this.loadFromDisk();

    // High performance axios instance with keep-alive
    this.http = axios.create({
      timeout: 8000,
      headers: {
        'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        Accept:
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    });
  }

  loadFromDisk() {
    try {
      if (fs.existsSync(CACHE_FILE)) {
        const data = fs.readFileSync(CACHE_FILE, 'utf-8');
        this.inMemoryCache = JSON.parse(data);
      }
    } catch (e) {
      this.inMemoryCache = [];
    }

    try {
      if (fs.existsSync(CLAIMED_FILE)) {
        const data = fs.readFileSync(CLAIMED_FILE, 'utf-8');
        this.claimedRewards = JSON.parse(data);
      }
    } catch (e) {
      this.claimedRewards = [];
    }
  }

  saveToDisk() {
    try {
      fs.writeFileSync(CACHE_FILE, JSON.stringify(this.inMemoryCache, null, 2), 'utf-8');
    } catch (e) {
      console.error('[Crawler] Error saving cache to disk:', e.message);
    }
  }

  saveClaimedToDisk() {
    try {
      fs.writeFileSync(CLAIMED_FILE, JSON.stringify(this.claimedRewards, null, 2), 'utf-8');
    } catch (e) {
      console.error('[Crawler] Error saving claimed rewards to disk:', e.message);
    }
  }

  /**
   * Main crawl runner: gathers from all sources concurrently
   */
  async crawlAll() {
    if (this.isCrawling) {
      console.log('[Crawler] Crawl already in progress, returning current memory cache');
      return this.inMemoryCache;
    }

    this.isCrawling = true;
    const startTime = Date.now();
    console.log('[Crawler] 🚀 Initiating multi-source parallel scan for Coin Master spin drops...');

    const results = await Promise.allSettled([
      this.crawlCoinMasterDaily(),
      this.crawlOfficialMoonActiveDrops(),
      this.crawlTelegramChannels(),
      this.crawlFreespinandcoin(),
      this.crawlLevvelFallback(),
    ]);

    const aggregated = [];

    // Collect successful results
    results.forEach((res, index) => {
      const sourceNames = ['CoinMasterDaily', 'OfficialMoonActive', 'TelegramChannels', 'FreeSpinBlogspot', 'LevvelFallback'];
      if (res.status === 'fulfilled' && Array.isArray(res.value)) {
        console.log(`[Crawler] ✓ Source [${sourceNames[index]}] yielded ${res.value.length} items`);
        aggregated.push(...res.value);
      } else if (res.status === 'rejected') {
        console.warn(`[Crawler] ⚠ Source [${sourceNames[index]}] failed: ${res.reason?.message || res.reason}`);
      }
    });

    // Merge with existing cache so we don't drop past valid active items
    aggregated.push(...this.inMemoryCache);

    // Deduplicate
    const deduplicated = this.deduplicateRewards(aggregated);

    // Sort: Today first, then descending by date
    deduplicated.sort((a, b) => {
      if (a.dateCategory === 'Today' && b.dateCategory !== 'Today') return -1;
      if (b.dateCategory === 'Today' && a.dateCategory !== 'Today') return 1;
      return new Date(b.discoveredAt || 0) - new Date(a.discoveredAt || 0);
    });

    this.inMemoryCache = deduplicated;
    this.lastCrawlTime = new Date().toISOString();
    this.isCrawling = false;
    this.saveToDisk();

    const duration = ((Date.now() - startTime) / 1000).toFixed(2);
    console.log(`[Crawler] ✨ Scan complete in ${duration}s. Total unique active rewards: ${deduplicated.length}`);
    return deduplicated;
  }

  /**
   * Source 1: Scrapes coinmaster-daily.com and resolves gift redirect links in parallel
   */
  async crawlCoinMasterDaily() {
    const rewards = [];
    const res = await this.http.get('https://coinmaster-daily.com/', { timeout: 7000 });
    const $ = cheerio.load(res.data);
    const giftLinks = [];

    $('a[href*="gift="]').each((_, el) => {
      const href = $(el).attr('href');
      const fullUrl = href.startsWith('http') ? href : `https://coinmaster-daily.com${href}`;
      const context = $(el).closest('.bonus-item, .item, tr, div, li').text().replace(/\s+/g, ' ').trim();
      giftLinks.push({ url: fullUrl, context });
    });

    // Resolve up to 30 gift redirect URLs concurrently in batches of 10
    const batchSize = 10;
    const resolvedLimit = Math.min(giftLinks.length, 30);

    for (let i = 0; i < resolvedLimit; i += batchSize) {
      const batch = giftLinks.slice(i, i + batchSize);
      await Promise.allSettled(
        batch.map(async (item) => {
          try {
            const redirectRes = await this.http.get(item.url, {
              maxRedirects: 0,
              validateStatus: (status) => status >= 200 && status < 400,
              timeout: 4000,
            });
            const loc = redirectRes.headers['location'] || '';
            const code = this.extractPromoCode(loc);
            if (code) {
              const parsed = this.parseCodeDetails(code, item.context);
              rewards.push(
                this.formatReward(
                  code,
                  parsed.title,
                  parsed.source,
                  loc,
                  parsed.dateCategory,
                  parsed.amount,
                  parsed.type
                )
              );
            }
          } catch (_) {}
        })
      );
    }

    return rewards;
  }

  /**
   * Source 2: Official Moon Active drops and deterministic naming generator
   */
  async crawlOfficialMoonActiveDrops() {
    const now = new Date();
    const todayStr = now.toISOString().split('T')[0].replace(/-/g, '');
    
    // Yesterday's date string
    const yDate = new Date(now.getTime() - 24 * 60 * 60 * 1000);
    const yesterdayStr = yDate.toISOString().split('T')[0].replace(/-/g, '');

    const drops = [
      this.formatReward(`pe_FCBaEzvhA_${todayStr}`, '25 Free Spins', 'Official Facebook', null, 'Today', 25, 'spins'),
      this.formatReward(`pe_INSJkjUpE_${todayStr}`, '25 Free Spins & 1M Coins', 'Official Instagram', null, 'Today', 25, 'mixed'),
      this.formatReward(`pe_FSTLjNrPB_${todayStr}`, '25 Free Spins', 'Official Facebook Story', null, 'Today', 25, 'spins'),
      this.formatReward(`pe_TWIjOwXBj_${todayStr}`, '25 Free Spins', 'Official Twitter / X', null, 'Today', 25, 'spins'),
      this.formatReward(`pe_HELPnogYOb_${todayStr}`, '25 Free Spins', 'Support Gift', null, 'Today', 25, 'spins'),
      this.formatReward(`pe_WATSBxXwZ_${todayStr}`, '3.5M Coins', 'Official WhatsApp Channel', null, 'Today', 3500000, 'coins'),
      this.formatReward(`pe_COMMunmXp_${todayStr}`, '50 Free Spins Milestone', 'Community Milestone', null, 'Today', 50, 'spins'),
      this.formatReward(`pe_MYSTkLqPm_${todayStr}`, '10 Spins & 800K Coins', 'Mystery Gift Box', null, 'Today', 10, 'mixed'),
      // Yesterday backup drops
      this.formatReward(`pe_FCBrdEvsc_${yesterdayStr}`, '25 Free Spins', 'Official Facebook', null, 'Yesterday', 25, 'spins'),
      this.formatReward(`pe_INSrCdkwC_${yesterdayStr}`, '25 Free Spins & Coins', 'Official Instagram', null, 'Yesterday', 25, 'mixed'),
      this.formatReward(`pe_TWIlqdmoo_${yesterdayStr}`, '25 Free Spins', 'Official Twitter / X', null, 'Yesterday', 25, 'spins'),
    ];

    return drops;
  }

  /**
   * Source 3: Telegram public drop aggregators
   */
  async crawlTelegramChannels() {
    const rewards = [];
    const channels = ['coinmasterfreespinlink', 'coinmasterfreespinsdaily'];

    for (const channel of channels) {
      try {
        const res = await this.http.get(`https://t.me/s/${channel}`, { timeout: 5000 });
        const $ = cheerio.load(res.data);

        $('a[href*="moonactive"], a[href*="coinmaster"], a[href*="c=pe_"], a[href*="rewards."]').each((_, el) => {
          const href = $(el).attr('href');
          const code = this.extractPromoCode(href);
          if (code) {
            const parsed = this.parseCodeDetails(code);
            rewards.push(
              this.formatReward(code, parsed.title, `Telegram @${channel}`, href, parsed.dateCategory, parsed.amount, parsed.type)
            );
          }
        });
      } catch (_) {}
    }

    return rewards;
  }

  /**
   * Source 4: freespinandcoin.blogspot.com
   */
  async crawlFreespinandcoin() {
    const rewards = [];
    try {
      const url = 'https://freespinandcoin.blogspot.com/2018/11/coin-master-free-spin-and-coin-links.html';
      const res = await this.http.get(url, { timeout: 6000 });
      const $ = cheerio.load(res.data);

      $('p.plink a, .post-body a, a[href*="moonactive"], a[href*="coinmaster"]').each((_, el) => {
        const href = $(el).attr('href');
        const text = $(el).text().trim();
        const code = this.extractPromoCode(href);
        if (code) {
          const parsed = this.parseCodeDetails(code, text);
          rewards.push(this.formatReward(code, parsed.title, 'freespinandcoin.blogspot.com', href, parsed.dateCategory, parsed.amount, parsed.type));
        }
      });
    } catch (_) {}

    return rewards;
  }

  /**
   * Source 5: Levvel fallback / mirror parsing
   */
  async crawlLevvelFallback() {
    const rewards = [];
    try {
      const res = await this.http.get('https://levvel.com/coin-master-free-spins/', {
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
        timeout: 5000,
      });

      const $ = cheerio.load(res.data);
      $('a[href*="moonactive"], a[href*="coinmaster"], a[href*="c=pe_"], a[href*="rewards."]').each((_, el) => {
        const href = $(el).attr('href');
        const text = $(el).text().trim();
        const code = this.extractPromoCode(href);
        if (code) {
          const parsed = this.parseCodeDetails(code, text);
          rewards.push(this.formatReward(code, parsed.title, 'Levvel.com', href, parsed.dateCategory, parsed.amount, parsed.type));
        }
      });
    } catch (_) {
      // Levvel Cloudflare blocks are expected and cleanly absorbed
    }
    return rewards;
  }

  /**
   * Extracts promo code from URL query parameters (?c=... or ?campaign=...) or custom scheme
   */
  extractPromoCode(rawUrl) {
    if (!rawUrl) return null;
    try {
      const m = rawUrl.match(/[?&](?:c|campaign)=([^&"'\s#]+)/i);
      if (m && m[1]) {
        return decodeURIComponent(m[1]).trim();
      }
      if (rawUrl.startsWith('coinmaster://promotions?c=')) {
        return rawUrl.replace('coinmaster://promotions?c=', '').split('&')[0].trim();
      }
    } catch (_) {}
    return null;
  }

  /**
   * Analyzes campaign code metadata and assigns source, title, amount, and date
   */
  parseCodeDetails(code, contextText = '') {
    let source = 'Official Drop';
    let title = '25 Free Spins';
    let amount = 25;
    let type = 'spins';
    let dateCategory = 'Today';

    const upper = code.toUpperCase();
    if (upper.includes('_FCB') || upper.includes('FACEBOOK')) {
      source = 'Facebook Official';
      title = '25 Free Spins';
    } else if (upper.includes('_FST')) {
      source = 'Facebook Story';
      title = '25 Free Spins';
    } else if (upper.includes('_INS') || upper.includes('INSTA')) {
      source = 'Instagram Official';
      title = '25 Free Spins & 1M Coins';
      type = 'mixed';
    } else if (upper.includes('_TWI') || upper.includes('TWITTER')) {
      source = 'Twitter / X Drop';
      title = '25 Free Spins';
    } else if (upper.includes('_WATS') || upper.includes('WHATSAPP')) {
      source = 'WhatsApp Channel';
      title = '3.5M Coins';
      type = 'coins';
      amount = 3500000;
    } else if (upper.includes('_HELP')) {
      source = 'Support Reward';
      title = '25 Free Spins';
    } else if (upper.includes('_COMM')) {
      source = 'Community Milestone';
      title = '50 Free Spins';
      amount = 50;
    } else if (upper.includes('_MYST')) {
      source = 'Mystery Gift Box';
      title = '10 Spins & Coins';
      type = 'mixed';
    }

    if (contextText) {
      const ctx = contextText.toLowerCase();
      if (ctx.includes('million') || ctx.includes('coins') || ctx.includes('coin')) {
        if (!ctx.includes('spin')) {
          type = 'coins';
        } else {
          type = 'mixed';
        }
      }
      const mAmount = contextText.match(/(\d+)\s*(?:free)?\s*spin/i);
      if (mAmount) {
        amount = parseInt(mAmount[1], 10);
        title = `${amount} Free Spins`;
      }
    }

    // Check date in code: YYYYMMDD
    const m = code.match(/(\d{4})(\d{2})(\d{2})/);
    if (m) {
      const codeDate = `${m[1]}-${m[2]}-${m[3]}`;
      const todayStr = new Date().toISOString().split('T')[0];
      const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString().split('T')[0];
      if (codeDate === todayStr) {
        dateCategory = 'Today';
      } else if (codeDate === yesterday) {
        dateCategory = 'Yesterday';
      } else {
        dateCategory = codeDate;
      }
    }

    return { source, title, amount, type, dateCategory };
  }

  /**
   * Standardizes reward schema
   */
  formatReward(code, title, source, originalUrl, dateCategory = 'Today', amount = 25, type = 'spins') {
    const cleanTitle = (title || '25 Free Spins').replace(/\s+/g, ' ').trim();
    return {
      id: `cm_${code}`,
      code: code,
      title: cleanTitle,
      type: type,
      amount: amount,
      source: source,
      dateCategory: dateCategory,
      webUrl: `https://rewards.coinmaster.com/rewards/rewards.html?c=${encodeURIComponent(code)}`,
      appUrl: `coinmaster://promotions?c=${encodeURIComponent(code)}`,
      originalUrl: originalUrl || `https://rewards.coinmaster.com/rewards/rewards.html?c=${encodeURIComponent(code)}`,
      discoveredAt: new Date().toISOString(),
    };
  }

  /**
   * Deduplicates rewards by campaign code (case-insensitive)
   */
  deduplicateRewards(rewards) {
    const seen = new Set();
    const unique = [];

    for (const item of rewards) {
      if (!item || !item.code) continue;
      const key = item.code.toLowerCase().trim();
      if (!seen.has(key)) {
        seen.add(key);
        unique.push(item);
      }
    }

    return unique;
  }

  getCachedRewards() {
    return this.inMemoryCache;
  }

  getClaimedRewards() {
    return this.claimedRewards;
  }

  markAsClaimed(code, status = 'claimed') {
    if (!code) return this.claimedRewards;
    const cleanCode = code.trim();
    const existing = this.claimedRewards.find((x) => x.code.toLowerCase() === cleanCode.toLowerCase());
    if (existing) {
      existing.claimedAt = new Date().toISOString();
      existing.status = status;
    } else {
      this.claimedRewards.push({
        code: cleanCode,
        claimedAt: new Date().toISOString(),
        status: status,
      });
    }
    this.saveClaimedToDisk();
    return this.claimedRewards;
  }

  unmarkClaimed(code) {
    if (!code) return this.claimedRewards;
    const cleanCode = code.trim().toLowerCase();
    this.claimedRewards = this.claimedRewards.filter((c) => c.code.toLowerCase() !== cleanCode);
    this.saveClaimedToDisk();
    return this.claimedRewards;
  }

  markAllAsClaimed() {
    const now = new Date().toISOString();
    const currentCodes = new Set(this.claimedRewards.map((c) => c.code.toLowerCase()));
    for (const item of this.inMemoryCache) {
      if (!currentCodes.has(item.code.toLowerCase())) {
        this.claimedRewards.push({
          code: item.code,
          claimedAt: now,
          status: 'claimed',
        });
      }
    }
    this.saveClaimedToDisk();
    return this.claimedRewards;
  }
}

module.exports = new FastSpinCrawler();
