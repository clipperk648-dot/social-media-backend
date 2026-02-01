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
