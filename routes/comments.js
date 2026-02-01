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
