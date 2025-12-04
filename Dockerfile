###############################
# 1. Builder Stage
###############################
FROM node:22-alpine AS builder

WORKDIR /app

# Copy only package files to install deps
COPY package*.json ./

# Install ALL dependencies (including dev)
RUN npm ci

# Copy the rest of the source code
COPY . .

# Build NestJS
RUN npm run build


###############################
# 2. Production Stage
###############################
FROM node:22-alpine AS runner

WORKDIR /app

# Copy package files again for prod deps
COPY package*.json ./

# Install ONLY production dependencies
RUN npm ci --only=production

# Copy build output from builder
COPY --from=builder /app/dist ./dist

# Optional: add non-root user for security
RUN adduser -D nestuser
USER nestuser

EXPOSE 5000

CMD ["node", "dist/main.js"]
