// middleware/notFound.js
// Catches any request that didn't match a registered route.
// Register this BEFORE the errorHandler in server.js.

const notFound = (req, res, next) => {
  const error = new Error(`Route not found: ${req.originalUrl}`);
  error.statusCode = 404;
  next(error); // Pass to the global errorHandler
};

module.exports = notFound;
