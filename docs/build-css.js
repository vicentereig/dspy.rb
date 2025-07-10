#!/usr/bin/env node

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// Ensure output directory exists
const outputDir = path.join(__dirname, 'output/_bridgetown/static/css');
if (!fs.existsSync(outputDir)) {
  fs.mkdirSync(outputDir, { recursive: true });
}

// Build CSS with Tailwind
console.log('🎨 Building CSS with Tailwind...');
try {
  execSync(`npx tailwindcss -i frontend/styles/index.css -o ${outputDir}/index.css --minify`, {
    stdio: 'inherit',
    cwd: __dirname
  });
  console.log('✅ CSS built successfully!');
} catch (error) {
  console.error('❌ CSS build failed:', error.message);
  process.exit(1);
}