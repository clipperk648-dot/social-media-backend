#!/data/data/com.termux/files/usr/bin/bash

echo "📝 Creating remaining route files..."

# Create routes/users.js
cat > routes/users.js << 'EOF'
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
EOF

echo "✅ routes/users.js"

# Create routes/google.js
cat > routes/google.js << 'EOF'
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
EOF

echo "✅ routes/google.js"

# Create routes/notifications.js
cat > routes/notifications.js << 'EOF'
const express = require('express');
const router = express.Router();
const Notification = require('../models/Notification');
const authMiddleware = require('../middleware/auth');

router.get('/', authMiddleware, async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const notifications = await Notification.find({ recipient: req.userId })
      .sort({ createdAt: -1 })
      .limit(limit * 1)
      .skip((page - 1) * limit)
      .populate('sender', 'username fullName profilePicture')
      .populate('post', 'type caption mediaFiles')
      .exec();
    const count = await Notification.countDocuments({ recipient: req.userId });
    const unreadCount = await Notification.countDocuments({ recipient: req.userId, isRead: false });
    res.json({ notifications, unreadCount, totalPages: Math.ceil(count / limit), currentPage: page });
  } catch (error) {
    console.error('Error fetching notifications:', error);
    res.status(500).json({ error: 'Failed to fetch notifications' });
  }
});

router.put('/:notificationId/read', authMiddleware, async (req, res) => {
  try {
    const notification = await Notification.findOneAndUpdate(
      { _id: req.params.notificationId, recipient: req.userId },
      { isRead: true },
      { new: true }
    );
    if (!notification) {
      return res.status(404).json({ error: 'Notification not found' });
    }
    res.json({ message: 'Notification marked as read', notification });
  } catch (error) {
    console.error('Error marking notification as read:', error);
    res.status(500).json({ error: 'Failed to mark notification as read' });
  }
});

router.put('/read-all', authMiddleware, async (req, res) => {
  try {
    await Notification.updateMany({ recipient: req.userId, isRead: false }, { isRead: true });
    res.json({ message: 'All notifications marked as read' });
  } catch (error) {
    console.error('Error marking all notifications as read:', error);
    res.status(500).json({ error: 'Failed to mark notifications as read' });
  }
});

router.delete('/:notificationId', authMiddleware, async (req, res) => {
  try {
    const notification = await Notification.findOneAndDelete({
      _id: req.params.notificationId,
      recipient: req.userId
    });
    if (!notification) {
      return res.status(404).json({ error: 'Notification not found' });
    }
    res.json({ message: 'Notification deleted successfully' });
  } catch (error) {
    console.error('Error deleting notification:', error);
    res.status(500).json({ error: 'Failed to delete notification' });
  }
});

module.exports = router;
EOF

echo "✅ routes/notifications.js"

# Create routes/comments.js
cat > routes/comments.js << 'EOF'
const express = require('express');
const router = express.Router();
const Comment = require('../models/Comment');
const Post = require('../models/Post');
const Notification = require('../models/Notification');
const googleSheetsService = require('../services/googleSheets');
const authMiddleware = require('../middleware/auth');

router.post('/:postId', authMiddleware, async (req, res) => {
  try {
    const { text } = req.body;
    const postId = req.params.postId;
    if (!text || text.trim().length === 0) {
      return res.status(400).json({ error: 'Comment text is required' });
    }
    const post = await Post.findById(postId);
    if (!post) {
      return res.status(404).json({ error: 'Post not found' });
    }
    const comment = new Comment({ post: postId, author: req.userId, text: text.trim() });
    await comment.save();
    post.commentsCount += 1;
    await post.save();
    try {
      await googleSheetsService.updatePostStats(postId, { commentsCount: post.commentsCount });
    } catch (error) {
      console.error('Failed to update comment count in Google Sheets:', error);
    }
    if (post.author.toString() !== req.userId) {
      const notification = new Notification({
        recipient: post.author,
        sender: req.userId,
        type: 'comment',
        post: postId,
        comment: comment._id,
        message: 'commented on your post'
      });
      await notification.save();
    }
    await comment.populate('author', 'username fullName profilePicture');
    res.status(201).json({ message: 'Comment added successfully', comment });
  } catch (error) {
    console.error('Error adding comment:', error);
    res.status(500).json({ error: 'Failed to add comment' });
  }
});

router.get('/:postId', authMiddleware, async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const postId = req.params.postId;
    const comments = await Comment.find({ post: postId, parentComment: null })
      .sort({ createdAt: -1 })
      .limit(limit * 1)
      .skip((page - 1) * limit)
      .populate('author', 'username fullName profilePicture isVerified')
      .populate({ path: 'replies', populate: { path: 'author', select: 'username fullName profilePicture isVerified' } })
      .exec();
    const count = await Comment.countDocuments({ post: postId, parentComment: null });
    res.json({ comments, totalPages: Math.ceil(count / limit), currentPage: page });
  } catch (error) {
    console.error('Error fetching comments:', error);
    res.status(500).json({ error: 'Failed to fetch comments' });
  }
});

module.exports = router;
EOF

echo "✅ routes/comments.js"

echo ""
echo "🎉 ALL FILES CREATED SUCCESSFULLY!"
echo ""
echo "📊 Final Summary:"
echo "  ✅ 4 Models (User, Post, Comment, Notification)"
echo "  ✅ 1 Middleware (auth)"
echo "  ✅ 6 Routes (auth, posts, users, google, notifications, comments)"
echo "  ✅ 2 Services (googleSheets, googleDrive)"
echo "  ✅ 1 Script (initGoogleSheets)"
echo ""
echo "🚀 Your backend is ready!"
echo ""
echo "Next steps:"
echo "1. Configure your .env file"
echo "2. Run: npm install"
echo "3. Run: npm run init-sheets"
echo "4. Run: npm start"
echo ""

