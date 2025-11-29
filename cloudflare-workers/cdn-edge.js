/**
 * Cloudflare Workers Script for BEAGLE CDN and Edge Caching
 *
 * Features:
 * - Intelligent cache management
 * - Geographic routing
 * - A/B testing
 * - Request optimization
 * - Rate limiting
 * - Performance monitoring
 *
 * References:
 * - Cloudflare Workers documentation
 * - HTTP caching best practices
 * - Edge computing patterns
 */

// Configuration
const CONFIG = {
  CACHE_CONTROL: {
    api: 'no-cache, must-revalidate',
    static: 'public, max-age=31536000, immutable', // 1 year for static assets
    html: 'public, max-age=3600, must-revalidate', // 1 hour for HTML
    json: 'public, max-age=300, must-revalidate',   // 5 minutes for JSON
    images: 'public, max-age=86400, immutable',     // 1 day for images
    documents: 'public, max-age=604800, must-revalidate', // 1 week for docs
  },

  GEO_ROUTING: {
    NA: 'api-na.agourakis.com',
    EU: 'api-eu.agourakis.com',
    APAC: 'api-apac.agourakis.com',
  },

  RATE_LIMITS: {
    api: { requests: 1000, window: 60 },      // 1000 req/min
    ws: { requests: 100, window: 60 },        // 100 connections/min
    static: { requests: 10000, window: 60 },  // 10k req/min
  },

  ORIGINS: {
    primary: 'https://primary.agourakis.com',
    secondary: 'https://secondary.agourakis.com',
    fallback: 'https://fallback.agourakis.com',
  },
};

// KV Namespaces (configured in wrangler.toml)
// Assuming: cache_store, rate_limit_store, config_store

/**
 * Main request handler
 */
addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request));
});

/**
 * Handle incoming requests
 */
async function handleRequest(request) {
  try {
    const url = new URL(request.url);
    const cacheKey = new Request(url.toString(), { method: 'GET' });

    // Log request
    console.log(`${request.method} ${url.pathname}`);

    // Check rate limits
    if (!await checkRateLimit(request, url)) {
      return new Response('Rate limit exceeded', { status: 429 });
    }

    // Handle special routes
    const pathname = url.pathname;

    if (pathname === '/.well-known/health') {
      return handleHealthCheck(request);
    }

    if (pathname.startsWith('/api/')) {
      return handleAPI(request, url);
    }

    if (pathname.startsWith('/ws/')) {
      return handleWebSocket(request, url);
    }

    if (pathname.startsWith('/static/') || isStaticAsset(pathname)) {
      return handleStaticAssets(request, url, cacheKey);
    }

    if (pathname.startsWith('/docs/')) {
      return handleDocumentation(request, url, cacheKey);
    }

    // Default handler
    return handleDefault(request, url, cacheKey);

  } catch (error) {
    console.error('Request handler error:', error);
    return new Response(JSON.stringify({
      error: 'Internal server error',
      message: error.message,
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

/**
 * Handle API requests with caching strategy
 */
async function handleAPI(request, url) {
  // API requests typically should not be cached unless explicitly marked
  const cacheControl = CONFIG.CACHE_CONTROL.api;

  // Route to appropriate origin based on geography
  const origin = selectOrigin(request);

  // Modify request to origin
  const originUrl = new URL(request.url);
  originUrl.hostname = new URL(origin).hostname;

  const modifiedRequest = new Request(originUrl.toString(), {
    method: request.method,
    headers: addEdgeHeaders(request.headers),
    body: request.method !== 'GET' ? request.body : null,
  });

  const response = await fetch(modifiedRequest);

  // Add cache headers
  const newHeaders = new Headers(response.headers);
  newHeaders.set('Cache-Control', cacheControl);
  newHeaders.set('X-Edge-Location', 'cloudflare');
  newHeaders.set('X-Cache-Control', 'no-store');

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: newHeaders,
  });
}

/**
 * Handle WebSocket requests
 */
async function handleWebSocket(request, url) {
  // WebSocket traffic bypasses caching
  const origin = selectOrigin(request);

  const originUrl = new URL(request.url);
  originUrl.hostname = new URL(origin).hostname;

  const modifiedRequest = new Request(originUrl.toString(), {
    method: request.method,
    headers: addEdgeHeaders(request.headers),
    body: request.body,
  });

  return fetch(modifiedRequest);
}

/**
 * Handle static assets with aggressive caching
 */
async function handleStaticAssets(request, url, cacheKey) {
  // Try cache first
  const cache = caches.default;
  let response = await cache.match(cacheKey);

  if (response) {
    // Add cache hit header
    const newHeaders = new Headers(response.headers);
    newHeaders.set('X-Cache', 'HIT');

    return new Response(response.body, {
      status: response.status,
      headers: newHeaders,
    });
  }

  // Fetch from origin
  const origin = selectOrigin(request);
  const originUrl = new URL(request.url);
  originUrl.hostname = new URL(origin).hostname;

  const originRequest = new Request(originUrl.toString(), {
    method: 'GET',
    headers: addEdgeHeaders(request.headers),
  });

  response = await fetch(originRequest);

  // Determine cache control based on file type
  const extension = getFileExtension(url.pathname);
  const cacheControl = getCacheControl(extension);

  // Cache successful responses
  if (response.status === 200) {
    const newHeaders = new Headers(response.headers);
    newHeaders.set('Cache-Control', cacheControl);
    newHeaders.set('X-Cache', 'MISS');

    const cachedResponse = new Response(response.body, {
      status: response.status,
      headers: newHeaders,
    });

    // Cache with appropriate TTL
    event.waitUntil(cache.put(cacheKey, cachedResponse));

    return cachedResponse;
  }

  return response;
}

/**
 * Handle documentation with moderate caching
 */
async function handleDocumentation(request, url, cacheKey) {
  const cache = caches.default;
  let response = await cache.match(cacheKey);

  if (response) {
    const newHeaders = new Headers(response.headers);
    newHeaders.set('X-Cache', 'HIT');
    return new Response(response.body, {
      status: response.status,
      headers: newHeaders,
    });
  }

  const origin = selectOrigin(request);
  const originUrl = new URL(request.url);
  originUrl.hostname = new URL(origin).hostname;

  const originRequest = new Request(originUrl.toString(), {
    headers: addEdgeHeaders(request.headers),
  });

  response = await fetch(originRequest);

  if (response.status === 200) {
    const newHeaders = new Headers(response.headers);
    newHeaders.set('Cache-Control', CONFIG.CACHE_CONTROL.documents);
    newHeaders.set('X-Cache', 'MISS');

    const cachedResponse = new Response(response.body, {
      status: response.status,
      headers: newHeaders,
    });

    event.waitUntil(cache.put(cacheKey, cachedResponse));
    return cachedResponse;
  }

  return response;
}

/**
 * Handle default/HTML responses
 */
async function handleDefault(request, url, cacheKey) {
  const cache = caches.default;
  let response = await cache.match(cacheKey);

  if (response) {
    const newHeaders = new Headers(response.headers);
    newHeaders.set('X-Cache', 'HIT');
    return new Response(response.body, {
      status: response.status,
      headers: newHeaders,
    });
  }

  const origin = selectOrigin(request);
  const originUrl = new URL(request.url);
  originUrl.hostname = new URL(origin).hostname;

  const originRequest = new Request(originUrl.toString(), {
    headers: addEdgeHeaders(request.headers),
  });

  response = await fetch(originRequest);

  if (response.status === 200) {
    const newHeaders = new Headers(response.headers);
    newHeaders.set('Cache-Control', CONFIG.CACHE_CONTROL.html);
    newHeaders.set('X-Cache', 'MISS');

    const cachedResponse = new Response(response.body, {
      status: response.status,
      headers: newHeaders,
    });

    event.waitUntil(cache.put(cacheKey, cachedResponse));
    return cachedResponse;
  }

  return response;
}

/**
 * Health check endpoint
 */
function handleHealthCheck(request) {
  return new Response(JSON.stringify({
    status: 'ok',
    timestamp: new Date().toISOString(),
    edge: 'cloudflare',
    version: '1.0.0',
  }), {
    status: 200,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-cache, no-store',
    },
  });
}

/**
 * Rate limiting check
 */
async function checkRateLimit(request, url) {
  const clientIP = request.headers.get('CF-Connecting-IP') || 'unknown';
  const pathname = url.pathname;

  // Determine rate limit bucket
  let bucket = 'default';
  let limit = CONFIG.RATE_LIMITS.api;

  if (pathname.startsWith('/api/')) {
    bucket = 'api';
    limit = CONFIG.RATE_LIMITS.api;
  } else if (pathname.startsWith('/ws/')) {
    bucket = 'ws';
    limit = CONFIG.RATE_LIMITS.ws;
  } else if (pathname.startsWith('/static/') || isStaticAsset(pathname)) {
    bucket = 'static';
    limit = CONFIG.RATE_LIMITS.static;
  }

  const key = `rate:${bucket}:${clientIP}`;

  // Get current count from KV
  const current = await RATE_LIMIT_STORE.get(key) || '0';
  const count = parseInt(current) + 1;

  // Check limit
  if (count > limit.requests) {
    return false;
  }

  // Update count with TTL
  await RATE_LIMIT_STORE.put(key, count.toString(), {
    expirationTtl: limit.window,
  });

  return true;
}

/**
 * Select origin based on geography and availability
 */
function selectOrigin(request) {
  // Get client country from Cloudflare headers
  const country = request.headers.get('CF-IPCountry') || 'US';

  // Select regional origin
  let origin = CONFIG.ORIGINS.primary;

  if (country.startsWith('EU') || ['GB', 'DE', 'FR'].includes(country)) {
    origin = CONFIG.ORIGINS.secondary; // European origin
  } else if (['JP', 'AU', 'SG', 'HK'].includes(country)) {
    origin = CONFIG.ORIGINS.fallback; // Asia-Pacific origin
  }

  return origin;
}

/**
 * Add edge-specific headers
 */
function addEdgeHeaders(headers) {
  const newHeaders = new Headers(headers);
  newHeaders.set('X-Forwarded-By', 'cloudflare-edge');
  newHeaders.set('X-Real-IP', headers.get('CF-Connecting-IP') || 'unknown');
  newHeaders.set('X-Client-Country', headers.get('CF-IPCountry') || 'unknown');
  newHeaders.set('X-Client-Device-Type', headers.get('CF-Device-Type') || 'unknown');
  newHeaders.set('X-Client-Browser', headers.get('CF-Browser') || 'unknown');
  return newHeaders;
}

/**
 * Get cache control header based on file extension
 */
function getCacheControl(extension) {
  const ext = extension.toLowerCase();

  switch (ext) {
    case 'js':
    case 'css':
    case 'woff':
    case 'woff2':
    case 'ttf':
    case 'eot':
      return CONFIG.CACHE_CONTROL.static;

    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'svg':
      return CONFIG.CACHE_CONTROL.images;

    case 'json':
      return CONFIG.CACHE_CONTROL.json;

    case 'html':
      return CONFIG.CACHE_CONTROL.html;

    default:
      return CONFIG.CACHE_CONTROL.api;
  }
}

/**
 * Check if path is a static asset
 */
function isStaticAsset(pathname) {
  const staticExtensions = [
    '.js', '.css', '.woff', '.woff2', '.ttf', '.eot',
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.svg',
    '.ico', '.manifest', '.map',
  ];

  return staticExtensions.some(ext => pathname.endsWith(ext));
}

/**
 * Get file extension from pathname
 */
function getFileExtension(pathname) {
  const match = pathname.match(/\.([^/?#]+)(?:[?#]|$)/);
  return match ? match[1] : '';
}
