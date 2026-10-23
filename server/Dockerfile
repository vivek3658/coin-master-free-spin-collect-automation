# Multi-stage production build for ultra-high throughput Fastify Coin Master Engine
FROM node:22-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

FROM node:22-alpine AS runner

WORKDIR /app
ENV NODE_ENV=production \
    PORT=3000 \
    HOST=0.0.0.0 \
    NODE_OPTIONS="--max-old-space-size=8192"

# Install curl/wget and android platform-tools (adb) in container if mobile debugging via network
RUN apk add --no-cache curl android-tools

# Copy dependencies and application source
COPY --from=builder /app/node_modules ./node_modules
COPY . .

# Create data directory with proper write permissions
RUN mkdir -p /app/data && chown -R node:node /app

USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/api/health || exit 1

CMD ["node", "cluster.js"]
