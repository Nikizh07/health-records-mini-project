# ============================================================
# Dockerfile for Migrant Clinic Backend API
# ============================================================

# Step 1: Base image
# node:22-slim is an official lightweight Debian-based Node.js image (~180MB).
# It satisfies the Node >= 22 requirement of firebase-admin v14 and Prisma v7,
# while providing the standard glibc library Prisma requires to execute its
# Linux query engine binaries cleanly without Alpine/musl quirks.
FROM node:22-slim

# Install OpenSSL (required by Prisma engine to communicate with PostgreSQL)
RUN apt-get update -y && apt-get install -y openssl ca-certificates && rm -rf /var/lib/apt/lists/*

# Set working directory inside the container
WORKDIR /app

# Step 2: Leverage Docker layer caching for dependencies
# Copy package manifests first so npm install doesn't re-run on every code change
COPY package*.json ./

# Copy Prisma schema and config files required for code generation
COPY prisma ./prisma/
COPY prisma.config.ts ./

# Install dependencies (including devDependencies like 'prisma' needed for generation)
RUN npm install

# Step 3: Generate Prisma Client for the Linux container environment.
# Note: Prisma v7 evaluates prisma.config.ts during generate. Since .env is ignored
# (never baked into the image), we pass a placeholder DATABASE_URL just for this
# build step. Prisma generate does not connect to the database.
RUN DATABASE_URL="postgresql://placeholder:placeholder@localhost:5432/placeholder" npx prisma generate

# Step 4: Copy the rest of the application source code
COPY . .

# Step 5: Ensure uploads directory exists and set proper permissions
RUN mkdir -p /app/uploads/reports && chown -R node:node /app

# Step 6: Switch to non-root user for security best practices
USER node

# Step 7: Expose port and define entrypoint
# Default to 3000 locally; Cloud Run injects PORT=8080 automatically
ENV PORT=3000
EXPOSE 3000

# Start server using the standard start script (node server.js)
CMD ["npm", "start"]
