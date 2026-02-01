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
