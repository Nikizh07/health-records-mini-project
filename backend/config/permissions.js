// backend/config/permissions.js
// ============================================================
// The one permission table (AUTH_RBAC_CONSENT_PLAN.md §B)
// ============================================================
// Permission = can this role do this action at all. Scope (own clinic,
// own appointments, own profile) is checked in the controllers.
// The app receives the list in GET /patients/me and gates screens by it.
// ============================================================

'use strict';

const PERMISSIONS = {
  PATIENT: ['self:profile', 'consent:respond'],
  RECEPTIONIST: ['patient:register', 'patient:lookup', 'appointment:manage'],
  DOCTOR: [
    'patient:register', 'patient:lookup', 'appointment:manage',
    'record:read', 'record:write', 'interaction:check', 'report:upload',
    'consent:request', 'consent:emergency',
  ],
  CLINIC_ADMIN: [
    'patient:register', 'patient:lookup', 'appointment:manage',
    'staff:manage', 'clinic:update', 'audit:read',
  ],
  ADMIN: ['staff:manage', 'clinic:update', 'clinic:create', 'audit:read'],
};

/** Only an ACTIVE user has permissions; PENDING and DISABLED get none. */
function permissionsFor(role, status) {
  return status === 'ACTIVE' ? PERMISSIONS[role] || [] : [];
}

/**
 * Clinic scope for staff: only the platform ADMIN works across clinics.
 * Call it after a permission gate, so the user is already known to be staff.
 */
function outsideOwnClinic(user, clinicId) {
  return user.role !== 'ADMIN' && clinicId !== user.clinic_id;
}

module.exports = { PERMISSIONS, permissionsFor, outsideOwnClinic };
