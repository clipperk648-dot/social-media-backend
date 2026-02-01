#!/data/data/com.termux/files/usr/bin/bash

echo "🔧 Creating service files..."

# Create services/googleSheets.js
cat > services/googleSheets.js << 'EOF'
const { google } = require('googleapis');
const sheets = google.sheets('v4');

class GoogleSheetsService {
  constructor() {
    this.auth = new google.auth.GoogleAuth({
      credentials: {
        type: 'service_account',
        project_id: process.env.GOOGLE_PROJECT_ID,
        private_key_id: process.env.GOOGLE_PRIVATE_KEY_ID,
        private_key: process.env.GOOGLE_PRIVATE_KEY.replace(/\\n/g, '\n'),
        client_email: process.env.GOOGLE_CLIENT_EMAIL,
        client_id: process.env.GOOGLE_CLIENT_ID
      },
      scopes: ['https://www.googleapis.com/auth/spreadsheets']
    });
    this.spreadsheetId = process.env.GOOGLE_SPREADSHEET_ID;
  }

  async addPost(postData) {
    try {
      const authClient = await this.auth.getClient();
      const values = [[
        postData._id.toString(),
        postData.author.toString(),
        postData.type,
        postData.caption || '',
        postData.textContent || '',
        postData.likesCount,
        postData.commentsCount,
        postData.savedCount,
        new Date().toISOString()
      ]];
      const request = {
        spreadsheetId: this.spreadsheetId,
        range: 'Posts!A:I',
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
        resource: { values },
        auth: authClient
      };
      const response = await sheets.spreadsheets.values.append(request);
      return response.data;
    } catch (error) {
      console.error('Error adding post to Google Sheets:', error);
      throw error;
    }
  }

  async updatePostStats(postId, updates) {
    try {
      const authClient = await this.auth.getClient();
      const getRequest = {
        spreadsheetId: this.spreadsheetId,
        range: 'Posts!A:I',
        auth: authClient
      };
      const getResponse = await sheets.spreadsheets.values.get(getRequest);
      const rows = getResponse.data.values;
      let rowIndex = -1;
      for (let i = 0; i < rows.length; i++) {
        if (rows[i][0] === postId) {
          rowIndex = i + 1;
          break;
        }
      }
      if (rowIndex === -1) {
        throw new Error('Post not found in Google Sheets');
      }
      const updateData = [];
      if (updates.likesCount !== undefined) {
        updateData.push({ range: `Posts!F${rowIndex}`, values: [[updates.likesCount]] });
      }
      if (updates.commentsCount !== undefined) {
        updateData.push({ range: `Posts!G${rowIndex}`, values: [[updates.commentsCount]] });
      }
      if (updates.savedCount !== undefined) {
        updateData.push({ range: `Posts!H${rowIndex}`, values: [[updates.savedCount]] });
      }
      const batchUpdateRequest = {
        spreadsheetId: this.spreadsheetId,
        resource: { valueInputOption: 'USER_ENTERED', data: updateData },
        auth: authClient
      };
      const response = await sheets.spreadsheets.values.batchUpdate(batchUpdateRequest);
      return response.data;
    } catch (error) {
      console.error('Error updating post stats in Google Sheets:', error);
      throw error;
    }
  }

  async addUserLogin(userId, username, timestamp) {
    try {
      const authClient = await this.auth.getClient();
      const values = [[userId.toString(), username, timestamp, new Date().toISOString()]];
      const request = {
        spreadsheetId: this.spreadsheetId,
        range: 'Logins!A:D',
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
        resource: { values },
        auth: authClient
      };
      const response = await sheets.spreadsheets.values.append(request);
      return response.data;
    } catch (error) {
      console.error('Error logging user login to Google Sheets:', error);
      throw error;
    }
  }

  async updateUserStats(userId, stats) {
    try {
      const authClient = await this.auth.getClient();
      const values = [[
        userId.toString(),
        stats.followersCount || 0,
        stats.followingCount || 0,
        stats.postsCount || 0,
        new Date().toISOString()
      ]];
      const request = {
        spreadsheetId: this.spreadsheetId,
        range: 'UserStats!A:E',
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
        resource: { values },
        auth: authClient
      };
      const response = await sheets.spreadsheets.values.append(request);
      return response.data;
    } catch (error) {
      console.error('Error updating user stats in Google Sheets:', error);
      throw error;
    }
  }

  async initializeSpreadsheet() {
    try {
      const authClient = await this.auth.getClient();
      const postsHeaders = [['Post ID', 'Author ID', 'Type', 'Caption', 'Text Content', 'Likes', 'Comments', 'Saved', 'Created At']];
      const loginsHeaders = [['User ID', 'Username', 'Login Timestamp', 'Recorded At']];
      const userStatsHeaders = [['User ID', 'Followers Count', 'Following Count', 'Posts Count', 'Updated At']];
      
      await sheets.spreadsheets.values.update({
        spreadsheetId: this.spreadsheetId,
        range: 'Posts!A1:I1',
        valueInputOption: 'USER_ENTERED',
        resource: { values: postsHeaders },
        auth: authClient
      });
      
      await sheets.spreadsheets.values.update({
        spreadsheetId: this.spreadsheetId,
        range: 'Logins!A1:D1',
        valueInputOption: 'USER_ENTERED',
        resource: { values: loginsHeaders },
        auth: authClient
      });
      
      await sheets.spreadsheets.values.update({
        spreadsheetId: this.spreadsheetId,
        range: 'UserStats!A1:E1',
        valueInputOption: 'USER_ENTERED',
        resource: { values: userStatsHeaders },
        auth: authClient
      });
      
      console.log('✅ Google Sheets initialized successfully');
    } catch (error) {
      console.error('Error initializing Google Sheets:', error);
      throw error;
    }
  }
}

module.exports = new GoogleSheetsService();
EOF

echo "✅ services/googleSheets.js"

# Create services/googleDrive.js
cat > services/googleDrive.js << 'EOF'
const { google } = require('googleapis');

class GoogleDriveService {
  constructor() {
    this.oauth2Client = new google.auth.OAuth2(
      process.env.GOOGLE_CLIENT_ID,
      process.env.GOOGLE_CLIENT_SECRET,
      process.env.GOOGLE_REDIRECT_URI
    );
  }

  setUserCredentials(tokens) {
    this.oauth2Client.setCredentials(tokens);
  }

  async uploadFile(fileBuffer, fileName, mimeType, userTokens) {
    try {
      this.setUserCredentials(userTokens);
      const drive = google.drive({ version: 'v3', auth: this.oauth2Client });
      const appFolderName = 'SocialMediaApp';
      let folderId = await this.getOrCreateFolder(drive, appFolderName);
      const fileMetadata = { name: fileName, parents: [folderId] };
      const media = { mimeType: mimeType, body: fileBuffer };
      const file = await drive.files.create({
        resource: fileMetadata,
        media: media,
        fields: 'id, name, webViewLink, thumbnailLink, mimeType'
      });
      await drive.permissions.create({
        fileId: file.data.id,
        requestBody: { role: 'reader', type: 'anyone' }
      });
      return file.data;
    } catch (error) {
      console.error('Error uploading file to Google Drive:', error);
      throw error;
    }
  }

  async getOrCreateFolder(drive, folderName) {
    try {
      const response = await drive.files.list({
        q: `name='${folderName}' and mimeType='application/vnd.google-apps.folder' and trashed=false`,
        fields: 'files(id, name)',
        spaces: 'drive'
      });
      if (response.data.files.length > 0) {
        return response.data.files[0].id;
      }
      const fileMetadata = { name: folderName, mimeType: 'application/vnd.google-apps.folder' };
      const folder = await drive.files.create({ resource: fileMetadata, fields: 'id' });
      return folder.data.id;
    } catch (error) {
      console.error('Error getting or creating folder:', error);
      throw error;
    }
  }

  async deleteFile(fileId, userTokens) {
    try {
      this.setUserCredentials(userTokens);
      const drive = google.drive({ version: 'v3', auth: this.oauth2Client });
      await drive.files.delete({ fileId: fileId });
      return { success: true };
    } catch (error) {
      console.error('Error deleting file from Google Drive:', error);
      throw error;
    }
  }

  getAuthUrl() {
    const scopes = [
      'https://www.googleapis.com/auth/drive.file',
      'https://www.googleapis.com/auth/userinfo.profile'
    ];
    return this.oauth2Client.generateAuthUrl({
      access_type: 'offline',
      scope: scopes,
      prompt: 'consent'
    });
  }

  async getTokensFromCode(code) {
    try {
      const { tokens } = await this.oauth2Client.getToken(code);
      return tokens;
    } catch (error) {
      console.error('Error getting tokens from code:', error);
      throw error;
    }
  }

  async refreshAccessToken(refreshToken) {
    try {
      this.oauth2Client.setCredentials({ refresh_token: refreshToken });
      const { credentials } = await this.oauth2Client.refreshAccessToken();
      return credentials;
    } catch (error) {
      console.error('Error refreshing access token:', error);
      throw error;
    }
  }
}

module.exports = new GoogleDriveService();
EOF

echo "✅ services/googleDrive.js"

# Create scripts/initGoogleSheets.js
cat > scripts/initGoogleSheets.js << 'EOF'
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
EOF

echo "✅ scripts/initGoogleSheets.js"

echo ""
echo "✅ All services created!"
echo "📝 Files created so far:"
echo "  - 4 models"
echo "  - 1 middleware"
echo "  - 2 routes (auth, posts)"
echo "  - 2 services (googleSheets, googleDrive)"
echo "  - 1 script (initGoogleSheets)"
echo ""
echo "✨ Ready to create remaining routes!"
echo ""

