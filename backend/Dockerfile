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

# Step 5: RDS CA bundle, so the DATABASE_URL can use sslmode=verify-full
ADD https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /app/certs/rds-global-bundle.pem

# Step 6: Set proper permissions (the CA bundle lands root-owned and 0600)
RUN chmod 644 /app/certs/rds-global-bundle.pem && chown -R node:node /app

# Step 7: Switch to non-root user for security best practices
USER node

# Step 8: Expose port and define entrypoint
# ECS injects PORT via the task definition; 3000 is the local default.
ENV PORT=3000
EXPOSE 3000

# Apply pending migrations, then start the API. `prisma` is already installed
# in the image (devDependencies), so no extra deploy step is needed.
CMD ["sh", "-c", "npx prisma migrate deploy && node server.js"]
