const fastify = require('fastify');
const path = require('path');
const fs = require('fs');
const cron = require('node-cron');
const crypto = require('crypto');
const crawler = require('./crawler');
const autoClaimer = require('./auto-claimer');

// Initialize Fastify with high-throughput settings
const app = fastify({
  logger: process.env.NODE_ENV === 'test' ? false : { level: process.env.LOG_LEVEL || 'info' },
  keepAliveTimeout: 65000,
  routerOptions: {
    maxParamLength: 150,
  },
  trustProxy: true,
});

const PORT = parseInt(process.env.PORT || '3000', 10);
const HOST = process.env.HOST || '0.0.0.0';

// Register security & performance plugins
async function setupPlugins() {
  // 1. Helmet security headers (prevents XSS, clickjacking, MIME-sniffing, etc.)
  await app.register(require('@fastify/helmet'), {
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'", "'unsafe-inline'"],
        styleSrc: ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
        fontSrc: ["'self'", 'https://fonts.gstatic.com'],
        imgSrc: ["'self'", 'data:', 'https:'],
        connectSrc: ["'self'"],
        frameAncestors: ["'self'"],
      },
    },
    crossOriginEmbedderPolicy: false,
  });

  // 2. Strict CORS
  await app.register(require('@fastify/cors'), {
    origin: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    credentials: true,
  });

  // 3. Brotli and Gzip compression
  await app.register(require('@fastify/compress'), {
    encodings: ['br', 'gzip', 'deflate'],
    threshold: 1024,
  });

  // 4. Rate-limiting for DDoS / brute-force protection
  await app.register(require('@fastify/rate-limit'), {
    max: 2000,
    timeWindow: '1 minute',
    allowList: ['127.0.0.1', 'localhost', '::1'],
    errorResponseBuilder: (req, context) => ({
      statusCode: 429,
      error: 'Too Many Requests',
      message: `Rate limit exceeded. Try again in ${context.after}`,
    }),
  });

  // 5. Static file serving (Serves the sleek Lastwave-inspired web app)
  let staticPath = path.join(__dirname, '..', 'app', 'public');
  if (!fs.existsSync(staticPath)) {
    staticPath = path.join(__dirname, 'public');
  }

  await app.register(require('@fastify/static'), {
    root: staticPath,
    prefix: '/',
    maxAge: 3600000, // 1 hour client cache for static assets
  });
}

// Memory cache helper with ETag calculation
let cachedETag = '';
let cachedEnriched = [];

function refreshEnrichedCache() {
  const spins = crawler.getCachedRewards();
  const claimed = crawler.getClaimedRewards();
  const claimedMap = new Map(claimed.map((c) => [c.code.toLowerCase(), c]));

  cachedEnriched = spins.map((s) => {
    const claimInfo = claimedMap.get(s.code.toLowerCase());
    return {
      ...s,
      isClaimed: !!claimInfo,
      claimedAt: claimInfo ? claimInfo.claimedAt : null,
      claimStatus: claimInfo ? claimInfo.status : 'unclaimed',
    };
  });

  // Generate weak ETag for O(1) conditional responses
  const hash = crypto.createHash('md5').update(JSON.stringify(cachedEnriched)).digest('hex').substring(0, 16);
  cachedETag = `W/"${hash}"`;
}

// Setup background auto-sync cron: Runs every 5 minutes
cron.schedule('*/5 * * * *', async () => {
  app.log.info('[Cron] Automated 5-minute spin drop sync executing...');
  try {
    await crawler.crawlAll();
    refreshEnrichedCache();
    app.log.info(`[Cron] Sync finished. ${cachedEnriched.length} total rewards available.`);
  } catch (err) {
    app.log.warn(`[Cron] Background sync error: ${err.message}`);
  }
});

// Setup API Routes
function setupRoutes() {
  /**
   * Health Check Probe for Docker / Vercel / Kubernetes
   */
  app.get('/api/health', async (req, reply) => {
    return {
      status: 'ok',
      uptime: process.uptime(),
      timestamp: new Date().toISOString(),
      memoryUsage: process.memoryUsage(),
    };
  });

  /**
   * GET /api/spins
   * Ultra-fast in-memory lookup with ETag and Edge Cache headers
   */
  app.get(
    '/api/spins',
    {
      schema: {
        response: {
          200: {
            type: 'object',
            properties: {
              success: { type: 'boolean' },
              count: { type: 'number' },
              claimedCount: { type: 'number' },
              unclaimedCount: { type: 'number' },
              lastCrawlTime: { type: ['string', 'null'] },
              rewards: { type: 'array' },
            },
          },
        },
      },
    },
    async (req, reply) => {
      // Check ETag for 304 Not Modified
      const clientETag = req.headers['if-none-match'];
      if (clientETag && clientETag === cachedETag) {
        return reply.code(304).send();
      }

      reply.header('ETag', cachedETag);
      reply.header('Cache-Control', 'public, max-age=10, s-maxage=60, stale-while-revalidate=300');

      const claimedCount = cachedEnriched.filter((s) => s.isClaimed).length;
      return {
        success: true,
        count: cachedEnriched.length,
        claimedCount: claimedCount,
        unclaimedCount: cachedEnriched.length - claimedCount,
        lastCrawlTime: crawler.lastCrawlTime,
        rewards: cachedEnriched,
      };
    }
  );

  /**
   * GET /api/spins/today
   */
  app.get('/api/spins/today', async (req, reply) => {
    const todayRewards = cachedEnriched.filter((s) => s.dateCategory === 'Today');
    return {
      success: true,
      count: todayRewards.length,
      rewards: todayRewards,
    };
  });

  /**
   * POST /api/spins/refresh
   * Triggers an immediate multi-source live scan
   */
  app.post('/api/spins/refresh', async (req, reply) => {
    try {
      app.log.info('[API] Manual live rescan requested');
      await crawler.crawlAll();
      refreshEnrichedCache();
      return {
        success: true,
        count: cachedEnriched.length,
        rewards: cachedEnriched,
      };
    } catch (e) {
      reply.code(500);
      return { success: false, error: e.message };
    }
  });

  /**
   * POST /api/spins/claim/:code
   */
  app.post(
    '/api/spins/claim/:code',
    {
      schema: {
        params: {
          type: 'object',
          properties: {
            code: { type: 'string', pattern: '^[a-zA-Z0-9_.-]{3,128}$' },
          },
          required: ['code'],
        },
      },
    },
    async (req, reply) => {
      const { code } = req.params;
      crawler.markAsClaimed(code, 'claimed');
      refreshEnrichedCache();
      return { success: true, message: `Reward ${code} marked as claimed.` };
    }
  );

  /**
   * POST /api/spins/unclaim/:code
   */
  app.post(
    '/api/spins/unclaim/:code',
    {
      schema: {
        params: {
          type: 'object',
          properties: {
            code: { type: 'string', pattern: '^[a-zA-Z0-9_.-]{3,128}$' },
          },
          required: ['code'],
        },
      },
    },
    async (req, reply) => {
      const { code } = req.params;
      crawler.unmarkClaimed(code);
      refreshEnrichedCache();
      return { success: true, message: `Reward ${code} reset to unclaimed.` };
    }
  );

  /**
   * POST /api/spins/claim-all
   */
  app.post('/api/spins/claim-all', async (req, reply) => {
    crawler.markAllAsClaimed();
    refreshEnrichedCache();
    return { success: true, message: 'All current rewards marked as claimed.' };
  });

  /**
   * GET /api/adb/devices
   * Checks ADB or Termux connection to smartphone
   */
  app.get('/api/adb/devices', async (req, reply) => {
    const status = await autoClaimer.checkAdbConnection();
    return status;
  });

  /**
   * POST /api/adb/connect
   * Connect to wireless ADB via IP:port
   */
  app.post(
    '/api/adb/connect',
    {
      schema: {
        body: {
          type: 'object',
          properties: {
            ipPort: { type: 'string', pattern: '^[0-9.:]{7,25}$' },
          },
          required: ['ipPort'],
        },
      },
    },
    async (req, reply) => {
      const { ipPort } = req.body;
      const res = await autoClaimer.connectWireless(ipPort);
      return res;
    }
  );

  /**
   * POST /api/auto-claim/start
   * Starts sequential collection through smartphone cmd/intent with customizable delay
   */
  app.post(
    '/api/auto-claim/start',
    {
      schema: {
        body: {
          type: 'object',
          properties: {
            delay: { type: 'number', minimum: 2, maximum: 20 },
            deviceId: { type: 'string', pattern: '^[a-zA-Z0-9_.-]{0,64}$' },
          },
        },
      },
    },
    async (req, reply) => {
      const delay = req.body?.delay || 4;
      const deviceId = req.body?.deviceId || null;
      const result = await autoClaimer.startAutoClaim(delay, deviceId);
      refreshEnrichedCache();
      return result;
    }
  );

  /**
   * POST /api/auto-claim/stop
   * Emergency Stop button triggered from notification or UI
   */
  app.post('/api/auto-claim/stop', async (req, reply) => {
    const result = autoClaimer.stop();
    refreshEnrichedCache();
    return result;
  });

  /**
   * POST /api/auto-claim/pause
   */
  app.post('/api/auto-claim/pause', async (req, reply) => {
    return autoClaimer.pause();
  });

  /**
   * POST /api/auto-claim/resume
   */
  app.post('/api/auto-claim/resume', async (req, reply) => {
    return autoClaimer.resume();
  });

  /**
   * GET /api/auto-claim/status
   */
  app.get('/api/auto-claim/status', async (req, reply) => {
    return autoClaimer.getStatus();
  });
}

// Bootstrap server
async function start() {
  try {
    await setupPlugins();
    setupRoutes();

    // Initial cache population
    refreshEnrichedCache();
    if (cachedEnriched.length === 0) {
      crawler.crawlAll().then(() => {
        refreshEnrichedCache();
        app.log.info(`[Startup] Initial crawl ready with ${cachedEnriched.length} rewards.`);
      });
    }

    await app.listen({ port: PORT, host: HOST });
    console.log(`\n======================================================`);
    console.log(`🚀 Fastify Coin Master Engine active on http://${HOST}:${PORT}`);
    console.log(`⚡ Ultra-high throughput architecture ready`);
    console.log(`📱 Smartphone CMD & Intent Auto-Collector ready`);
    console.log(`======================================================\n`);
  } catch (err) {
    app.log.error(err);
    process.exit(1);
  }
}

// Export app for testing & Vercel serverless
module.exports = app;

if (require.main === module) {
  start();
}
