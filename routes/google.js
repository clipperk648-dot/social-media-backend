const express = require('express');
const router = express.Router();
const User = require('../models/User');
const googleDriveService = require('../services/googleDrive');
const authMiddleware = require('../middleware/auth');

router.get('/auth-url', authMiddleware, (req, res) => {
  try {
    const authUrl = googleDriveService.getAuthUrl();
    res.json({ authUrl });
  } catch (error) {
    console.error('Error generating auth URL:', error);
    res.status(500).json({ error: 'Failed to generate authorization URL' });
  }
});

router.post('/callback', authMiddleware, async (req, res) => {
  try {
    const { code } = req.body;
    if (!code) {
      return res.status(400).json({ error: 'Authorization code required' });
    }
    const tokens = await googleDriveService.getTokensFromCode(code);
    await User.findByIdAndUpdate(req.userId, {
      googleDriveConnected: true,
      googleDriveTokens: {
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        expiry_date: tokens.expiry_date
      }
    });
    res.json({ message: 'Google Drive connected successfully', connected: true });
  } catch (error) {
    console.error('Error handling OAuth callback:', error);
    res.status(500).json({ error: 'Failed to connect Google Drive' });
  }
});

router.get('/status', authMiddleware, async (req, res) => {
  try {
    const user = await User.findById(req.userId);
    res.json({
      connected: user.googleDriveConnected || false,
      hasValidTokens: !!(user.googleDriveTokens?.access_token)
    });
  } catch (error) {
    console.error('Error checking Google Drive status:', error);
    res.status(500).json({ error: 'Failed to check connection status' });
  }
});

router.post('/disconnect', authMiddleware, async (req, res) => {
  try {
    await User.findByIdAndUpdate(req.userId, {
      googleDriveConnected: false,
      googleDriveTokens: null
    });
    res.json({ message: 'Google Drive disconnected successfully', connected: false });
  } catch (error) {
    console.error('Error disconnecting Google Drive:', error);
    res.status(500).json({ error: 'Failed to disconnect Google Drive' });
  }
});

module.exports = router;
