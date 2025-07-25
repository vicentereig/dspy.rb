const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

async function generateOGImages() {
  const browser = await chromium.launch({ headless: true });
  const outputDir = path.join(__dirname, '../output/images/og');
  
  // Ensure output directory exists
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  try {
    const page = await browser.newPage();
    await page.setViewportSize({ width: 1200, height: 630 });

    // Generate default OG image
    console.log('Generating default OG image...');
    const defaultHtml = `
      <!DOCTYPE html>
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
            filter: drop-shadow(0 8px 16px rgba(0, 0, 0, 0.2));
          }
          
          .title {
            font-size: 80px;
            font-weight: 800;
            margin-bottom: 20px;
            text-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
            letter-spacing: -0.02em;
          }
          
          .tagline {
            font-size: 32px;
            font-weight: 300;
            opacity: 0.9;
            max-width: 800px;
            margin: 0 auto;
            text-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
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
      </html>
    `;

    await page.setContent(defaultHtml);
    await page.waitForTimeout(200);
    await page.screenshot({ path: path.join(outputDir, 'default.png') });
    console.log('Generated default.png');

    // Read articles metadata from output
    const articlesDir = path.join(__dirname, '../output/blog');
    if (fs.existsSync(articlesDir)) {
      const articleFiles = fs.readdirSync(articlesDir)
        .filter(f => f.endsWith('.html') && f !== 'index.html');

      for (const file of articleFiles) {
        const slug = file.replace('.html', '');
        console.log(`Generating OG image for ${slug}...`);
        
        // For now, generate a simple OG image with the slug
        const articleHtml = `
          <!DOCTYPE html>
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
                padding: 80px;
                display: flex;
                flex-direction: column;
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
              
              .content {
                position: relative;
                z-index: 10;
              }
              
              .title {
                font-size: 72px;
                font-weight: 800;
                line-height: 1.1;
                margin-bottom: 40px;
                text-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
                letter-spacing: -0.02em;
              }
              
              .branding {
                font-size: 24px;
                font-weight: 700;
                display: flex;
                align-items: center;
                gap: 12px;
                position: absolute;
                bottom: 80px;
                right: 80px;
              }
              
              .ruby-icon {
                width: 40px;
                height: 40px;
                background: white;
                border-radius: 8px;
                display: flex;
                align-items: center;
                justify-content: center;
                font-size: 24px;
                color: #dc2626;
                box-shadow: 0 3px 10px rgba(0, 0, 0, 0.2);
              }
            </style>
          </head>
          <body>
            <div class="decorative-bg"></div>
            <div class="content">
              <h1 class="title">${slug.replace(/-/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}</h1>
            </div>
            <div class="branding">
              <div class="ruby-icon">💎</div>
              <span>DSPy.rb</span>
            </div>
          </body>
          </html>
        `;

        await page.setContent(articleHtml);
        await page.waitForTimeout(200);
        await page.screenshot({ path: path.join(outputDir, `${slug}.png`) });
        console.log(`Generated ${slug}.png`);
      }
    }

    console.log('OG image generation complete!');
  } catch (error) {
    console.error('Error generating OG images:', error);
  } finally {
    await browser.close();
  }
}

generateOGImages();