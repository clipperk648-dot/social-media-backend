#!/data/data/com.termux/files/usr/bin/bash

echo "📦 Creating route files..."

# Create routes/auth.js
cat > routes/auth.js << 'EOF'
const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const User = require('../models/User');
const googleSheetsService = require('../services/googleSheets');

router.post('/register', async (req, res) => {
  try {
    const { username, email, password, fullName } = req.body;
    const existingUser = await User.findOne({ $or: [{ email }, { username }] });
    if (existingUser) {
      return res.status(400).json({ error: 'User with this email or username already exists' });
    }
    const user = new User({ username, email, password, fullName });
    await user.save();
    const token = jwt.sign({ userId: user._id }, process.env.JWT_SECRET || 'your-secret-key', { expiresIn: '7d' });
    try {
      await googleSheetsService.addUserLogin(user._id, username, 'registration');
    } catch (error) {
      console.error('Failed to log registration to Google Sheets:', error);
    }
    res.status(201).json({ message: 'User registered successfully', token, user: user.toJSON() });
  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ error: 'Registration failed' });
  }
});

router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    const user = await User.findOne({ email });
    if (!user) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }
    const isMatch = await user.comparePassword(password);
    if (!isMatch) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }
    const token = jwt.sign({ userId: user._id }, process.env.JWT_SECRET || 'your-secret-key', { expiresIn: '7d' });
    try {
      await googleSheetsService.addUserLogin(user._id, user.username, 'login');
    } catch (error) {
      console.error('Failed to log login to Google Sheets:', error);
    }
    res.json({ message: 'Login successful', token, user: user.toJSON() });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Login failed' });
  }
});

router.get('/verify', async (req, res) => {
  try {
    const token = req.headers.authorization?.split(' ')[1];
    if (!token) {
      return res.status(401).json({ error: 'No token provided' });
    }
    const decoded = jwt.verify(token, process.env.JWT_SECRET || 'your-secret-key');
    const user = await User.findById(decoded.userId);
    if (!user) {
      return res.status(401).json({ error: 'User not found' });
    }
    res.json({ valid: true, user: user.toJSON() });
  } catch (error) {
    res.status(401).json({ valid: false, error: 'Invalid token' });
  }
});

module.exports = router;
EOF

echo "✅ routes/auth.js"

# Create routes/posts.js - simplified version
cat > routes/posts.js << 'EOF'
const express = require('express');
const router = express.Router();
const multer = require('multer');
const Post = require('../models/Post');
const User = require('../models/User');
const Notification = require('../models/Notification');
const googleDriveService = require('../services/googleDrive');
const googleSheetsService = require('../services/googleSheets');
const authMiddleware = require('../middleware/auth');

const storage = multer.memoryStorage();
const upload = multer({ storage: storage, limits: { fileSize: 100 * 1024 * 1024 } });

router.post('/text', authMiddleware, async (req, res) => {
  try {
    const { textContent, caption, tags } = req.body;
    const post = new Post({
      author: req.userId,
      type: 'text',
      textContent,
      caption,
      tags: tags ? tags.split(',').map(tag => tag.trim()) : []
    });
    await post.save();
    await User.findByIdAndUpdate(req.userId, { $inc: { postsCount: 1 } });
    try {
      await googleSheetsService.addPost(post);
    } catch (error) {
      console.error('Failed to log post to Google Sheets:', error);
    }
    res.status(201).json({
      message: 'Text post created successfully',
      post: await post.populate('author', 'username fullName profilePicture')
    });
  } catch (error) {
    console.error('Error creating text post:', error);
    res.status(500).json({ error: 'Failed to create post' });
  }
});

router.post('/media', authMiddleware, upload.array('files', 10), async (req, res) => {
  try {
    const { caption, tags, type } = req.body;
    const files = req.files;
    const user = await User.findById(req.userId);
    
    if (!user.googleDriveConnected) {
      const notification = new Notification({
        recipient: req.userId,
        sender: req.userId,
        type: 'google_drive_required',
        message: 'Please connect your Google Drive to upload photos and videos',
        link: '/settings/google-drive'
      });
      await notification.save();
      return res.status(403).json({
        error: 'Google Drive connection required',
        message: 'Please connect your Google Drive account to upload media files',
        requireGoogleDrive: true,
        notificationCreated: true
      });
    }
    
    const mediaFiles = [];
    for (const file of files) {
      try {
        const uploadedFile = await googleDriveService.uploadFile(
          file.buffer,
          file.originalname,
          file.mimetype,
          user.googleDriveTokens
        );
        mediaFiles.push({
          fileId: uploadedFile.id,
          fileName: uploadedFile.name,
          mimeType: uploadedFile.mimeType,
          webViewLink: uploadedFile.webViewLink,
          thumbnailLink: uploadedFile.thumbnailLink
        });
      } catch (error) {
        console.error('Error uploading file to Google Drive:', error);
        if (error.message.includes('invalid_grant') || error.message.includes('expired')) {
          return res.status(401).json({
            error: 'Google Drive token expired',
            message: 'Please reconnect your Google Drive account',
            requireGoogleDrive: true
          });
        }
        throw error;
      }
    }
    
    const post = new Post({
      author: req.userId,
      type: type || 'image',
      caption,
      mediaFiles,
      tags: tags ? tags.split(',').map(tag => tag.trim()) : []
    });
    await post.save();
    await User.findByIdAndUpdate(req.userId, { $inc: { postsCount: 1 } });
    try {
      await googleSheetsService.addPost(post);
    } catch (error) {
      console.error('Failed to log post to Google Sheets:', error);
    }
    res.status(201).json({
      message: 'Media post created successfully',
      post: await post.populate('author', 'username fullName profilePicture')
    });
  } catch (error) {
    console.error('Error creating media post:', error);
    res.status(500).json({ error: 'Failed to create media post' });
  }
});

router.get('/feed', authMiddleware, async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const user = await User.findById(req.userId);
    const following = user.following || [];
    const posts = await Post.find({
      author: { $in: [...following, req.userId] },
      isArchived: false
    })
    .sort({ createdAt: -1 })
    .limit(limit * 1)
    .skip((page - 1) * limit)
    .populate('author', 'username fullName profilePicture isVerified')
    .exec();
    const count = await Post.countDocuments({
      author: { $in: [...following, req.userId] },
      isArchived: false
    });
    res.json({ posts, totalPages: Math.ceil(count / limit), currentPage: page });
  } catch (error) {
    console.error('Error fetching feed:', error);
    res.status(500).json({ error: 'Failed to fetch feed' });
  }
});

router.post('/:postId/like', authMiddleware, async (req, res) => {
  try {
    const post = await Post.findById(req.params.postId);
    if (!post) {
      return res.status(404).json({ error: 'Post not found' });
    }
    const isLiked = post.likes.includes(req.userId);
    if (isLiked) {
      post.likes = post.likes.filter(id => id.toString() !== req.userId);
      post.likesCount = Math.max(0, post.likesCount - 1);
    } else {
      post.likes.push(req.userId);
      post.likesCount += 1;
      if (post.author.toString() !== req.userId) {
        const notification = new Notification({
          recipient: post.author,
          sender: req.userId,
          type: 'like',
          post: post._id,
          message: 'liked your post'
        });
        await notification.save();
      }
    }
    await post.save();
    try {
      await googleSheetsService.updatePostStats(post._id.toString(), { likesCount: post.likesCount });
    } catch (error) {
      console.error('Failed to update post stats in Google Sheets:', error);
    }
    res.json({ liked: !isLiked, likesCount: post.likesCount });
  } catch (error) {
    console.error('Error liking post:', error);
    res.status(500).json({ error: 'Failed to like post' });
  }
});

module.exports = router;
EOF

echo "✅ routes/posts.js"

echo ""
echo "✅ Route files created!"
echo "🔧 Creating service files next..."
echo ""

