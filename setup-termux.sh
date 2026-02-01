#!/data/data/com.termux/files/usr/bin/bash

# Social Media Backend - Termux Setup Script
# This script automates the setup process for Termux

echo "================================================"
echo "  Social Media Backend - Termux Setup"
echo "================================================"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Update Termux packages
echo -e "${YELLOW}Step 1/6: Updating Termux packages...${NC}"
pkg update -y && pkg upgrade -y

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Termux packages updated successfully${NC}"
else
    echo -e "${RED}✗ Failed to update Termux packages${NC}"
    exit 1
fi

# Install Node.js
echo -e "${YELLOW}Step 2/6: Installing Node.js...${NC}"
pkg install nodejs -y

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Node.js installed successfully${NC}"
    node --version
    npm --version
else
    echo -e "${RED}✗ Failed to install Node.js${NC}"
    exit 1
fi

# Install Git
echo -e "${YELLOW}Step 3/6: Installing Git...${NC}"
pkg install git -y

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Git installed successfully${NC}"
    git --version
else
    echo -e "${RED}✗ Failed to install Git${NC}"
    exit 1
fi

# Install text editor (nano)
echo -e "${YELLOW}Step 4/6: Installing text editor (nano)...${NC}"
pkg install nano -y

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Nano installed successfully${NC}"
else
    echo -e "${RED}✗ Failed to install nano${NC}"
fi

# Install project dependencies
echo -e "${YELLOW}Step 5/6: Installing project dependencies...${NC}"
npm install

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Dependencies installed successfully${NC}"
else
    echo -e "${RED}✗ Failed to install dependencies${NC}"
    exit 1
fi

# Create .env file if it doesn't exist
echo -e "${YELLOW}Step 6/6: Setting up environment file...${NC}"
if [ ! -f .env ]; then
    cp .env.example .env
    echo -e "${GREEN}✓ Created .env file from template${NC}"
    echo -e "${YELLOW}⚠ IMPORTANT: Edit .env file with your actual credentials!${NC}"
    echo -e "Run: ${GREEN}nano .env${NC}"
else
    echo -e "${GREEN}✓ .env file already exists${NC}"
fi

echo ""
echo "================================================"
echo -e "${GREEN}  Setup Complete!${NC}"
echo "================================================"
echo ""
echo "Next steps:"
echo "1. Configure your .env file:"
echo -e "   ${GREEN}nano .env${NC}"
echo ""
echo "2. Follow GOOGLE_CLOUD_SETUP.md to set up Google Cloud"
echo ""
echo "3. Initialize Google Sheets:"
echo -e "   ${GREEN}npm run init-sheets${NC}"
echo ""
echo "4. Start the development server:"
echo -e "   ${GREEN}npm run dev${NC}"
echo ""
echo "5. Or start in production mode:"
echo -e "   ${GREEN}npm start${NC}"
echo ""
echo "For detailed setup instructions, see:"
echo "- GOOGLE_CLOUD_SETUP.md"
echo "- SETUP_GUIDE.md"
echo "- README.md"
echo ""
echo -e "${YELLOW}Happy coding! 🚀${NC}"
