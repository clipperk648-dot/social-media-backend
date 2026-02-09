const express = require('express');
const mongoose = require('mongoose');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://jah75397_db_user:tziRRTTNp1h1EgI@cluster0.21unmfv.mongodb.net/?appName=Cluster0';

mongoose.connect(MONGODB_URI)
  .then(() => console.log('Connected to MongoDB'))
  .catch((err) => console.error('MongoDB connection error:', err));

app.get('/', (req, res) => {
  res.json({ message: 'Backend API is running!' });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
