const express = require('express');
const router = express.Router();
const User = require('../models/User');
const Notification = require('../models/Notification');
const googleSheetsService = require('../services/googleSheets');
const authMiddleware = require('../middleware/auth');

router.get('/:username', authMiddleware, async (req, res) => {
  try {
    const user = await User.findOne({ username: req.params.username }).select('-password -googleDriveTokens');
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    const isFollowing = user.followers.includes(req.userId);
    res.json({ user, isFollowing });
  } catch (error) {
    console.error('Error fetching user profile:', error);
    res.status(500).json({ error: 'Failed to fetch user profile' });
  }
});

router.post('/:userId/follow', authMiddleware, async (req, res) => {
  try {
    const targetUserId = req.params.userId;
    if (targetUserId === req.userId) {
      return res.status(400).json({ error: 'Cannot follow yourself' });
    }
    const currentUser = await User.findById(req.userId);
    const targetUser = await User.findById(targetUserId);
    if (!targetUser) {
      return res.status(404).json({ error: 'User not found' });
    }
    const isFollowing = currentUser.following.includes(targetUserId);
    if (isFollowing) {
      currentUser.following = currentUser.following.filter(id => id.toString() !== targetUserId);
      currentUser.followingCount = Math.max(0, currentUser.followingCount - 1);
      targetUser.followers = targetUser.followers.filter(id => id.toString() !== req.userId);
      targetUser.followersCount = Math.max(0, targetUser.followersCount - 1);
    } else {
      currentUser.following.push(targetUserId);
      currentUser.followingCount += 1;
      targetUser.followers.push(req.userId);
      targetUser.followersCount += 1;
      const notification = new Notification({
        recipient: targetUserId,
        sender: req.userId,
        type: 'follow',
        message: 'started following you'
      });
      await notification.save();
    }
    await currentUser.save();
    await targetUser.save();
    try {
      await googleSheetsService.updateUserStats(req.userId, {
        followersCount: currentUser.followersCount,
        followingCount: currentUser.followingCount,
        postsCount: currentUser.postsCount
      });
      await googleSheetsService.updateUserStats(targetUserId, {
        followersCount: targetUser.followersCount,
        followingCount: targetUser.followingCount,
        postsCount: targetUser.postsCount
      });
    } catch (error) {
      console.error('Failed to update user stats in Google Sheets:', error);
    }
    res.json({ following: !isFollowing, followersCount: targetUser.followersCount });
  } catch (error) {
    console.error('Error following/unfollowing user:', error);
    res.status(500).json({ error: 'Failed to follow/unfollow user' });
  }
});

router.put('/profile', authMiddleware, async (req, res) => {
  try {
    const { fullName, bio, isPrivate } = req.body;
    const updates = {};
    if (fullName !== undefined) updates.fullName = fullName;
    if (bio !== undefined) updates.bio = bio;
    if (isPrivate !== undefined) updates.isPrivate = isPrivate;
    const user = await User.findByIdAndUpdate(req.userId, updates, { new: true }).select('-password -googleDriveTokens');
    res.json({ message: 'Profile updated successfully', user });
  } catch (error) {
    console.error('Error updating profile:', error);
    res.status(500).json({ error: 'Failed to update profile' });
  }
});

module.exports = router;
