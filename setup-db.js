require('dotenv').config();
const mongoose = require('mongoose');

const MONGODB_URI = process.env.MONGODB_URI;

// Define schemas
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
  type: { type: String, enum: ['like', 'comment', 'follow', 'drive_connect'] },
  message: String,
  read: { type: Boolean, default: false },
  createdAt: { type: Date, default: Date.now }
});

// Create models
const User = mongoose.model('User', userSchema);
const Post = mongoose.model('Post', postSchema);
const Comment = mongoose.model('Comment', commentSchema);
const Notification = mongoose.model('Notification', notificationSchema);

// Connect and create collections
async function setupDatabase() {
  try {
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB');
    
    console.log('✅ Collections created:');
    console.log('  - users');
    console.log('  - posts');
    console.log('  - comments');
    console.log('  - notifications');
    
    await mongoose.connection.close();
    console.log('✅ Setup complete!');
  } catch (error) {
    console.error('❌ Error:', error.message);
  }
}

setupDatabase();
