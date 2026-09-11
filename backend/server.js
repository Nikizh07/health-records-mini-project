// server.js — Entry point for the Migrant Clinic Backend API
// ============================================================
// ORDER OF OPERATIONS:
//   1. Load environment variables from .env
//   2. Create an Express app
//   3. Register global middleware (cors, body parser, logger)
//   4. Mount API routes
//   5. Register 404 and error-handling middleware (must be LAST)
//   6. Start the HTTP server on the configured port

'use strict';

// ── 1. Load environment variables FIRST (before anything else reads process.env)
require('dotenv').config();

const express = require('express');
const cors = require('cors');
const morgan = require('morgan');

const path = require('path');

const apiRoutes = require('./routes/index');
const notFound = require('./middleware/notFound');
const errorHandler = require('./middleware/errorHandler');

// ── 2. Initialise Express app
const app = express();

// ── 3. Global middleware
// CORS — allows your Flutter app / browser clients to call this API
app.use(cors());

// Body parsers — lets Express read JSON and URL-encoded request bodies
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Serve static uploaded files (reports, avatars, documents)
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// HTTP request logger — logs "GET /api/health 200 3ms" style lines in dev
if (process.env.NODE_ENV !== 'production') {
  app.use(morgan('dev'));
}

// ── 4. Mount API routes under /api prefix
//       e.g. GET /api/health
app.use('/api', apiRoutes);

// ── 5. Catch-all 404 (must be AFTER routes, BEFORE error handler)
app.use(notFound);

// ── 6. Global error handler (must be LAST, identified by 4 args)
app.use(errorHandler);

// ── 7. Start the server
const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log('==============================================');
  console.log(`🚀 Migrant Clinic API running on port ${PORT}`);
  console.log(`   Environment : ${process.env.NODE_ENV || 'development'}`);
  console.log(`   Health check: http://localhost:${PORT}/api/health`);
  console.log('==============================================');
});

// Export app for testing purposes (optional but good practice)
module.exports = app;
