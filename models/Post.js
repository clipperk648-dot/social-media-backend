const mongoose = require('mongoose');

const postSchema = new mongoose.Schema({
  author: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  type: { type: String, enum: ['text', 'image', 'video'], required: true },
  caption: { type: String, maxlength: 2000 },
  textContent: { type: String, maxlength: 5000 },
  mediaFiles: [{
    fileId: String,
    fileName: String,
    mimeType: String,
    webViewLink: String,
    thumbnailLink: String
  }],
  likes: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
  likesCount: { type: Number, default: 0 },
  commentsCount: { type: Number, default: 0 },
  savedBy: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
  savedCount: { type: Number, default: 0 },
  tags: [{ type: String, trim: true }],
  location: { type: String },
  isArchived: { type: Boolean, default: false },
  googleSheetRowId: { type: String }
}, { timestamps: true });

postSchema.index({ author: 1, createdAt: -1 });
postSchema.index({ tags: 1 });
postSchema.index({ createdAt: -1 });

module.exports = mongoose.model('Post', postSchema);
