const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

function generateHTML() {
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    
    body {
      width: 1200px;
      height: 630px;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      background: linear-gradient(135deg, #dc2626 0%, #7f1d1d 100%);
      color: white;
      position: relative;
      overflow: hidden;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    
    .decorative-bg {
      position: absolute;
      top: -50%;
      right: -30%;
      width: 100%;
      height: 200%;
      background: radial-gradient(circle, rgba(255,255,255,0.1) 0%, transparent 70%);
      transform: rotate(-30deg);
    }
    
    .container {
      text-align: center;
      position: relative;
      z-index: 10;
    }
    
    .logo {
      font-size: 120px;
      margin-bottom: 40px;
    }
    
    .title {
      font-size: 80px;
      font-weight: 800;
      margin-bottom: 20px;
      text-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
    }
    
    .tagline {
      font-size: 32px;
      font-weight: 300;
      opacity: 0.9;
      max-width: 800px;
      margin: 0 auto;
    }
  </style>
</head>
<body>
  <div class="decorative-bg"></div>
  <div class="container">
    <div class="logo">💎</div>
    <h1 class="title">DSPy.rb</h1>
    <p class="tagline">The Ruby Framework for Self-Improving Language Model Programs</p>
  </div>
</body>
</html>`;
}

async function generateDefaultOgImage() {
  // Generate into src so Bridgetown copies them
  const outputDir = path.join(__dirname, '../src/images/og');
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  
  await page.setViewportSize({ width: 1200, height: 630 });
  await page.setContent(generateHTML());
  await page.waitForTimeout(100);
  
  await page.screenshot({
    path: path.join(outputDir, 'default.png'),
    type: 'png'
  });

  await browser.close();
  console.log('Default OG image generated!');
}

generateDefaultOgImage().catch(console.error);