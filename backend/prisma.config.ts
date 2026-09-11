// prisma/prisma.config.ts
// Prisma v7+ requires the database URL to be configured here
// instead of schema.prisma's datasource block.
// This file is auto-detected by the Prisma CLI.

import 'dotenv/config';
import { defineConfig, env } from 'prisma/config';

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
  },
  datasource: {
    url: env('DATABASE_URL'),
  },
});
