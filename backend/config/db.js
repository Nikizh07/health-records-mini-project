// config/db.js
// Creates and exports a shared PostgreSQL connection pool.
//
// WHY A POOL?
// Opening a new database connection for every request is expensive (slow + wastes resources).
// A "pool" keeps a set of connections open and reuses them, which is standard practice.
//
// The 'pg' library reads the DATABASE_URL from your .env file automatically
// when you pass it as the 'connectionString' option.

const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  // For Google Cloud SQL with SSL (you'll enable this when connecting to Cloud SQL):
  // ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

// Test the connection on startup (optional but helpful during development)
pool.connect((err, client, release) => {
  if (err) {
    console.error('⚠️  Database connection error:', err.message);
    console.warn('   (This is OK for now — set DATABASE_URL in your .env to connect)');
    return;
  }
  console.log('✅ PostgreSQL database connected successfully');
  release(); // Release the client back to the pool
});

module.exports = pool;
