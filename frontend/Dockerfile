FROM node:20-alpine AS builder

WORKDIR /app

# Copy dependency manifests first for layer caching
COPY package.json package-lock.json ./

RUN npm ci

# Copy the rest of the source
COPY . .

# Build the production bundle
RUN npm run build

# ── Production runner ──────────────────────────────────────────────────────────
FROM node:20-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production

# Copy only what Next.js needs to serve the built app
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json

EXPOSE 3000

CMD ["npm", "start"]
