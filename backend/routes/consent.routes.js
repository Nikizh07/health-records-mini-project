// backend/routes/consent.routes.js
// ============================================================
// Patient consent (/api/consents) and the access audit (/api/audit)
// See controllers/consent.controller.js for the flows.
// ============================================================

'use strict';

const express = require('express');

const authenticate = require('../middleware/authenticate');
const requirePermission = require('../middleware/requirePermission');
const ctrl = require('../controllers/consent.controller');

const consentRouter = express.Router();
consentRouter.use(authenticate);

// Literal paths before /:id.
consentRouter.post('/', requirePermission('consent:request'), ctrl.requestConsent);
consentRouter.post('/redeem', requirePermission('consent:request'), ctrl.redeemShareCode);
consentRouter.post('/emergency', requirePermission('consent:emergency'), ctrl.emergencyAccess);
consentRouter.get('/pending', requirePermission('consent:respond'), ctrl.pendingConsents);
consentRouter.post('/share-code', requirePermission('consent:respond'), ctrl.createShareCode);
consentRouter.get('/mine', requirePermission('consent:respond'), ctrl.myConsents);
consentRouter.get('/:id', requirePermission('consent:request'), ctrl.getConsent);
consentRouter.post('/:id/respond', requirePermission('consent:respond'), ctrl.respondToConsent);
consentRouter.post('/:id/revoke', requirePermission('consent:respond'), ctrl.revokeConsent);

const auditRouter = express.Router();
auditRouter.use(authenticate);
auditRouter.get('/access', requirePermission('audit:read'), ctrl.accessAudit);

module.exports = { consentRouter, auditRouter };
