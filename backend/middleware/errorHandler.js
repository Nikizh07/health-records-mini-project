// middleware/errorHandler.js
// Global error-handling middleware for Express.
// Express identifies error handlers by their 4-argument signature: (err, req, res, next)
// This MUST be registered LAST in server.js, after all routes.

const errorHandler = (err, req, res, next) => {
  // Log the full error stack in development for debugging
  if (process.env.NODE_ENV !== 'production') {
    console.error('❌ Error:', err.stack);
  }

  const statusCode = err.statusCode || 500;
  const message = err.message || 'Internal Server Error';

  res.status(statusCode).json({
    status: 'error',
    statusCode,
    message,
    // Only expose stack trace in development
    ...(process.env.NODE_ENV !== 'production' && { stack: err.stack }),
  });
};

module.exports = errorHandler;
