require('dotenv').config();
const googleSheetsService = require('../services/googleSheets');

async function initializeGoogleSheets() {
  try {
    console.log('🔄 Initializing Google Sheets...');
    await googleSheetsService.initializeSpreadsheet();
    console.log('✅ Google Sheets initialized successfully!');
    console.log('\nCreated sheets:');
    console.log('- Posts (for post data)');
    console.log('- Logins (for user login tracking)');
    console.log('- UserStats (for follower/following counts)');
    console.log('\nYou can now start using the backend!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error initializing Google Sheets:', error);
    process.exit(1);
  }
}

initializeGoogleSheets();
