// backend/middleware/requirePermission.js
// ============================================================
// Permission gate: passes when the user holds ANY of the listed permissions.
//   router.post('/', requirePermission('record:write'), ctrl.create);
//   router.get('/:id', requirePermission('self:profile', 'record:read'), ctrl.get);
// Permissions come from config/permissions.js via authenticate().
// ============================================================

'use strict';

function requirePermission(...allowed) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({
        success: false,
        error: 'Unauthorized',
        message: 'Authentication required prior to permission check.',
      });
    }

    if (!allowed.some((p) => req.user.permissions?.includes(p))) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden',
        message: `Access denied. Requires permission: ${allowed.join(' or ')}.`,
      });
    }

    return next();
  };
}

module.exports = requirePermission;
