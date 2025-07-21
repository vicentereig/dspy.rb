const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

// Function to extract frontmatter from markdown files
function extractFrontmatter(content) {
  const frontmatterRegex = /^---\s*\n([\s\S]*?)\n---/;
  const match = content.match(frontmatterRegex);
  
  if (!match) return null;
  
  const frontmatter = {};
  const lines = match[1].split('\n');
  
  lines.forEach(line => {
    const colonIndex = line.indexOf(':');
    if (colonIndex > 0) {
      const key = line.substring(0, colonIndex).trim();
      let value = line.substring(colonIndex + 1).trim();
      
      // Remove quotes if present
      if ((value.startsWith('"') && value.endsWith('"')) || 
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1);
      }
      
      frontmatter[key] = value;
    }
  });
  
  return frontmatter;
}

// Function to format date
function formatDate(dateStr) {
  const date = new Date(dateStr);
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 
                  'July', 'August', 'September', 'October', 'November', 'December'];
  return `${months[date.getMonth()]} ${date.getDate()}, ${date.getFullYear()}`;
}

// Function to get category from frontmatter
function getCategory(frontmatter) {
  // Try different possible fields for category
  if (frontmatter.category) return frontmatter.category;
  if (frontmatter.categories) {
    // Handle array format like: [patterns, agents]
    const categories = frontmatter.categories.replace(/[\[\]]/g, '').split(',')[0].trim();
    return categories.charAt(0).toUpperCase() + categories.slice(1);
  }
  return 'Article';
}

// Function to get articles from source files
async function getArticles() {
  const articlesDir = path.join(__dirname, '../src/_articles');
  const articles = [];
  
  try {
    const files = fs.readdirSync(articlesDir).filter(file => file.endsWith('.md'));
    
    for (const file of files) {
      const filePath = path.join(articlesDir, file);
      const content = fs.readFileSync(filePath, 'utf-8');
      const frontmatter = extractFrontmatter(content);
      
      if (frontmatter) {
        const slug = file.replace('.md', '');
        const rawDate = frontmatter.date || new Date().toISOString();
        articles.push({
          slug,
          title: frontmatter.title || frontmatter.name || 'Untitled',
          description: frontmatter.description || '',
          category: getCategory(frontmatter),
          author: frontmatter.author || 'Vicente Reig',
          date: formatDate(rawDate),
          rawDate: rawDate // Keep raw date for sorting
        });
      }
    }
    
    // Sort by date (newest first)
    articles.sort((a, b) => new Date(b.rawDate) - new Date(a.rawDate));
    
  } catch (error) {
    console.error('Error reading articles:', error);
  }
  
  return articles;
}

function generateHTML(article) {
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
    }
    
    .container {
      padding: 80px;
      height: 100%;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      position: relative;
      z-index: 10;
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
    
    .header {
      display: flex;
      align-items: center;
      gap: 20px;
      margin-bottom: 40px;
    }
    
    .category-badge {
      background: rgba(255, 255, 255, 0.2);
      padding: 8px 20px;
      border-radius: 24px;
      font-size: 18px;
      font-weight: 600;
      backdrop-filter: blur(10px);
      border: 1px solid rgba(255, 255, 255, 0.3);
    }
    
    .content {
      flex: 1;
      display: flex;
      flex-direction: column;
      justify-content: center;
    }
    
    .title {
      font-size: 72px;
      font-weight: 800;
      line-height: 1.1;
      margin-bottom: 24px;
      text-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
    }
    
    .description {
      font-size: 28px;
      line-height: 1.4;
      opacity: 0.9;
      font-weight: 300;
      max-width: 900px;
    }
    
    .footer {
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    
    .author-info {
      display: flex;
      align-items: center;
      gap: 16px;
    }
    
    .author-avatar {
      width: 56px;
      height: 56px;
      border-radius: 50%;
      background: white;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 24px;
      font-weight: 700;
      color: #dc2626;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
    }
    
    .author-details {
      display: flex;
      flex-direction: column;
    }
    
    .author-name {
      font-size: 20px;
      font-weight: 600;
    }
    
    .publish-date {
      font-size: 16px;
      opacity: 0.8;
    }
    
    .branding {
      font-size: 24px;
      font-weight: 700;
      display: flex;
      align-items: center;
      gap: 12px;
    }
    
    .ruby-icon {
      width: 32px;
      height: 32px;
      background: white;
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 20px;
      color: #dc2626;
    }
  </style>
</head>
<body>
  <div class="decorative-bg"></div>
  <div class="container">
    <div class="header">
      <div class="category-badge">${article.category}</div>
    </div>
    
    <div class="content">
      <h1 class="title">${article.title}</h1>
      <p class="description">${article.description}</p>
    </div>
    
    <div class="footer">
      <div class="author-info">
        <div class="author-avatar">${article.author[0]}</div>
        <div class="author-details">
          <div class="author-name">${article.author}</div>
          <div class="publish-date">${article.date}</div>
        </div>
      </div>
      <div class="branding">
        <div class="ruby-icon">💎</div>
        <span>DSPy.rb</span>
      </div>
    </div>
  </div>
</body>
</html>`;
}

async function generateOgImages() {
  // Get articles dynamically from source files
  const articles = await getArticles();
  
  if (articles.length === 0) {
    console.log('No articles found to generate OG images for.');
    return;
  }
  
  console.log(`Found ${articles.length} articles to process.`);
  
  // Ensure output directory exists
  const outputDir = path.join(__dirname, '../output/images/og');
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  // Launch browser
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  
  // Set viewport to OG image dimensions
  await page.setViewportSize({ width: 1200, height: 630 });

  for (const article of articles) {
    console.log(`Generating OG image for: ${article.slug}`);
    console.log(`  Title: ${article.title}`);
    console.log(`  Category: ${article.category}`);
    console.log(`  Date: ${article.date}`);
    
    // Generate HTML
    const html = generateHTML(article);
    
    // Navigate to HTML
    await page.setContent(html);
    
    // Wait for any animations/fonts
    await page.waitForTimeout(100);
    
    // Take screenshot
    await page.screenshot({
      path: path.join(outputDir, `${article.slug}.png`),
      type: 'png'
    });
  }

  await browser.close();
  console.log('OG image generation complete!');
}

// Run the script
generateOgImages().catch(console.error);