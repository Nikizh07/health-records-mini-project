// controllers/health.controller.js
// Handles the business logic for the GET /api/health endpoint.
// A controller receives the request (req), builds a response, and sends it back (res).

/**
 * @desc    Returns server health status
 * @route   GET /api/health
 * @access  Public
 */
const getHealthStatus = (req, res) => {
  res.status(200).json({
    status: 'ok',
    message: 'Migrant Clinic API is running',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development',
  });
};

module.exports = { getHealthStatus };
