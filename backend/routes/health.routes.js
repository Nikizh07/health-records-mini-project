// routes/health.routes.js
// Defines the GET / route for the health check endpoint.
// Mounted at /api/health in server.js via the main router.

const express = require('express');
const router = express.Router();
const { getHealthStatus } = require('../controllers/health.controller');

router.get('/', getHealthStatus);

module.exports = router;
