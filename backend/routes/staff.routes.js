// backend/routes/staff.routes.js
// ============================================================
// Staff onboarding router (AUTH_RBAC_CONSENT_PLAN.md Phase 3)
// ============================================================
//   POST /api/staff/applications        signed-in, verified email, no account
//   POST /api/staff/invites             staff:manage
//   GET  /api/staff/invites             staff:manage
//   GET  /api/staff?status=             staff:manage
//   POST /api/staff/:userId/approve     staff:manage
//   POST /api/staff/:userId/reject      staff:manage
//   POST /api/staff/:userId/disable     staff:manage
// CLINIC_ADMIN is limited to their own clinic in the controller.
// ============================================================

'use strict';

const express = require('express');
const router = express.Router();

const authenticate = require('../middleware/authenticate');
const requirePermission = require('../middleware/requirePermission');
const staffCtrl = require('../controllers/staff.controller');

router.use(authenticate);

// No permission: the applicant has no account (and so no role) yet.
router.post('/applications', staffCtrl.applyAsDoctor);

const manage = requirePermission('staff:manage');
router.post('/invites', manage, staffCtrl.createInvite);
router.get('/invites', manage, staffCtrl.listInvites);
router.get('/', manage, staffCtrl.listStaff);
router.post('/:userId/approve', manage, staffCtrl.approveStaff);
router.post('/:userId/reject', manage, staffCtrl.rejectStaff);
router.post('/:userId/disable', manage, staffCtrl.disableStaff);

module.exports = router;
