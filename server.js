require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const { google } = require('googleapis');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// MongoDB Connection
mongoose.connect(process.env.MONGODB_URI)
  .then(() => console.log('✅ Connected to MongoDB'))
  .catch(err => console.error('❌ MongoDB Error:', err));

// MongoDB Schemas
const userSchema = new mongoose.Schema({
  username: { type: String, required: true, unique: true },
  email: { type: String, required: true, unique: true },
  password: { type: String, required: true },
  googleDriveConnected: { type: Boolean, default: false },
  driveRefreshToken: String,
  followers: { type: Number, default: 0 },
  following: { type: Number, default: 0 },
  createdAt: { type: Date, default: Date.now }
});

const postSchema = new mongoose.Schema({
  userId: { type: String, required: true },
  username: String,
  content: String,
  mediaType: { type: String, enum: ['text', 'image', 'video'] },
  mediaUrl: String,
  likes: { type: Number, default: 0 },
  comments: { type: Number, default: 0 },
  saved: { type: Number, default: 0 },
  createdAt: { type: Date, default: Date.now }
});

const commentSchema = new mongoose.Schema({
  postId: { type: String, required: true },
  userId: { type: String, required: true },
  username: String,
  text: { type: String, required: true },
  createdAt: { type: Date, default: Date.now }
});

const notificationSchema = new mongoose.Schema({
  userId: { type: String, required: true },
  type: String,
  message: String,
  read: { type: Boolean, default: false },
  createdAt: { type: Date, default: Date.now }
});

const User = mongoose.model('User', userSchema);
const Post = mongoose.model('Post', postSchema);
const Comment = mongoose.model('Comment', commentSchema);
const Notification = mongoose.model('Notification', notificationSchema);

// Google Sheets Setup
const credentials = JSON.parse(fs.readFileSync('./credentials.json'));
const auth = new google.auth.GoogleAuth({
  credentials,
  scopes: ['https://www.googleapis.com/auth/spreadsheets']
});

const sheets = google.sheets({ version: 'v4', auth });

// Helper: Write to Google Sheets
async function writeToSheet(sheetId, range, values) {
  try {
    await sheets.spreadsheets.values.append({
      spreadsheetId: sheetId,
      range: range,
      valueInputOption: 'RAW',
      resource: { values: [values] }
    });
  } catch (error) {
    console.error('Google Sheets Error:', error.message);
  }
}

// ========== API ROUTES ==========

// Health Check
app.get('/', (req, res) => {
  res.json({ message: '🚀 Social Media Backend is running!' });
});

// User Registration
app.post('/api/users/register', async (req, res) => {
  try {
    const { username, email, password } = req.body;
    
    const user = new User({ username, email, password });
    await user.save();
    
    // Save to Google Sheets - Logins
    await writeToSheet(
      process.env.GOOGLE_SHEET_LOGINS,
      'A:E',
      [user._id.toString(), username, email, password, new Date().toISOString()]
    );
    
    res.status(201).json({ success: true, userId: user._id, username });
  } catch (error) {
    res.status(400).json({ success: false, error: error.message });
  }
});

// User Login
app.post('/api/users/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    const user = await User.findOne({ email, password });
    
    if (!user) {
      return res.status(401).json({ success: false, error: 'Invalid credentials' });
    }
    
    res.json({ 
      success: true, 
      userId: user._id, 
      username: user.username,
      googleDriveConnected: user.googleDriveConnected
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Create Post
app.post('/api/posts', async (req, res) => {
  try {
    const { userId, username, content, mediaType, mediaUrl } = req.body;
    
    // Check if user needs to connect Google Drive for media posts
    if ((mediaType === 'image' || mediaType === 'video') && mediaUrl) {
      const user = await User.findById(userId);
      if (!user.googleDriveConnected) {
        return res.status(403).json({ 
          success: false, 
          error: 'Please connect your Google Drive first',
          requireDriveConnection: true
        });
      }
    }
    
    const post = new Post({ userId, username, content, mediaType, mediaUrl });
    await post.save();
    
    // Save to Google Sheets - Posts
    await writeToSheet(
      process.env.GOOGLE_SHEET_POSTS,
      'A:H',
      [
        post._id.toString(),
        userId,
        username,
        content || '',
        mediaType,
        mediaUrl || '',
        0, // likes
        new Date().toISOString()
      ]
    );
    
    res.status(201).json({ success: true, post });
  } catch (error) {
    res.status(400).json({ success: false, error: error.message });
  }
});

// Get All Posts
app.get('/api/posts', async (req, res) => {
  try {
    const posts = await Post.find().sort({ createdAt: -1 });
    res.json({ success: true, posts });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get Single Post
app.get('/api/posts/:postId', async (req, res) => {
  try {
    const { postId } = req.params;
    const post = await Post.findById(postId);
    res.json({ success: true, post });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Like Post
app.post('/api/posts/:postId/like', async (req, res) => {
  try {
    const { postId } = req.params;
    const { userId } = req.body;
    
    const post = await Post.findById(postId);
    post.likes += 1;
    await post.save();
    
    // Update Google Sheets - UserStats
    await writeToSheet(
      process.env.GOOGLE_SHEET_USERSTATS,
      'A:D',
      [userId, 'like', postId, new Date().toISOString()]
    );
    
    // Create notification
    const notification = new Notification({
      userId: post.userId,
      type: 'like',
      message: `Someone liked your post`,
      read: false
    });
    await notification.save();
    
    res.json({ success: true, likes: post.likes });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Save Post
app.post('/api/posts/:postId/save', async (req, res) => {
  try {
    const { postId } = req.params;
    
    const post = await Post.findById(postId);
    post.saved += 1;
    await post.save();
    
    res.json({ success: true, saved: post.saved });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Add Comment
app.post('/api/posts/:postId/comments', async (req, res) => {
  try {
    const { postId } = req.params;
    const { userId, username, text } = req.body;
    
    const comment = new Comment({ postId, userId, username, text });
    await comment.save();
    
    const post = await Post.findById(postId);
    post.comments += 1;
    await post.save();
    
    // Create notification
    const notification = new Notification({
      userId: post.userId,
      type: 'comment',
      message: `${username} commented on your post`,
      read: false
    });
    await notification.save();
    
    res.status(201).json({ success: true, comment });
  } catch (error) {
    res.status(400).json({ success: false, error: error.message });
  }
});

// Get Comments for Post
app.get('/api/posts/:postId/comments', async (req, res) => {
  try {
    const { postId } = req.params;
    const comments = await Comment.find({ postId }).sort({ createdAt: -1 });
    res.json({ success: true, comments });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Connect Google Drive
app.post('/api/users/:userId/connect-drive', async (req, res) => {
  try {
    const { userId } = req.params;
    const { refreshToken } = req.body;
    
    const user = await User.findById(userId);
    user.googleDriveConnected = true;
    user.driveRefreshToken = refreshToken;
    await user.save();
    
    // Create notification
    const notification = new Notification({
      userId,
      type: 'drive_connect',
      message: 'Google Drive connected successfully!',
      read: false
    });
    await notification.save();
    
    res.json({ success: true, message: 'Google Drive connected' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get User Profile
app.get('/api/users/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const user = await User.findById(userId).select('-password');
    res.json({ success: true, user });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get Notifications
app.get('/api/users/:userId/notifications', async (req, res) => {
  try {
    const { userId } = req.params;
    const notifications = await Notification.find({ userId }).sort({ createdAt: -1 });
    res.json({ success: true, notifications });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Mark Notification as Read
app.put('/api/notifications/:notificationId/read', async (req, res) => {
  try {
    const { notificationId } = req.params;
    const notification = await Notification.findById(notificationId);
    notification.read = true;
    await notification.save();
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Follow User
app.post('/api/users/:userId/follow', async (req, res) => {
  try {
    const { userId } = req.params;
    const { followerId } = req.body;
    
    const userToFollow = await User.findById(userId);
    const follower = await User.findById(followerId);
    
    userToFollow.followers += 1;
    follower.following += 1;
    
    await userToFollow.save();
    await follower.save();
    
    // Update Google Sheets - UserStats
    await writeToSheet(
      process.env.GOOGLE_SHEET_USERSTATS,
      'A:D',
      [userId, follower.username, userToFollow.followers, new Date().toISOString()]
    );
    
    // Create notification
    const notification = new Notification({
      userId: userId,
      type: 'follow',
      message: `${follower.username} started following you`,
      read: false
    });
    await notification.save();
    
    res.json({ success: true, followers: userToFollow.followers });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get User Posts
app.get('/api/users/:userId/posts', async (req, res) => {
  try {
    const { userId } = req.params;
    const posts = await Post.find({ userId }).sort({ createdAt: -1 });
    res.json({ success: true, posts });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Start Server
app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`📡 API: http://localhost:${PORT}`);
  console.log(`📊 MongoDB: Connected`);
  console.log(`📄 Google Sheets: Configured`);
});
