// backend/middleware/requireRole.js
// ============================================================
// Role-Based Authorization Middleware Factory
// ============================================================
// Restricts route access to users holding one of the specified roles.
// Usage examples:
//   router.get('/doctor-only', authenticate, requireRole('DOCTOR'), controller);
//   router.get('/staff-only', authenticate, requireRole('DOCTOR', 'ADMIN'), controller);
// ============================================================

'use strict';

/**
 * Higher-order middleware function that returns an Express middleware middleware
 * enforcing role-based access control.
 *
 * @param {...string} allowedRoles - List of permitted roles e.g. ('DOCTOR', 'ADMIN')
 */
function requireRole(...allowedRoles) {
  return (req, res, next) => {
    // 1. Ensure authenticate middleware has already run
    if (!req.user) {
      return res.status(401).json({
        success: false,
        error: 'Unauthorized',
        message: 'Authentication required prior to role check.',
      });
    }

    const userRole = (req.user.role || 'PATIENT').toUpperCase();
    const normalizedAllowedRoles = allowedRoles.map((role) => role.toUpperCase());

    // 2. Verify authorization
    if (!normalizedAllowedRoles.includes(userRole)) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden',
        message: `Access denied. Role "${userRole}" is not authorized for this action. Required role(s): ${allowedRoles.join(', ')}.`,
      });
    }

    // 3. Authorized, continue to next handler
    return next();
  };
}

module.exports = requireRole;
