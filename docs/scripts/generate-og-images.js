const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

// Articles data
const articles = [
  {
    slug: 'union-types-agentic-workflows',
    title: 'Why Union Types Transform AI Agent Development',
    description: 'How DSPy.rb\'s single-field union types with automatic type detection simplify AI agent development',
    category: 'Patterns',
    author: 'Vicente Reig',
    date: 'July 20, 2025'
  },
  {
    slug: 'type-safe-prediction-objects',
    title: 'Ship AI Features with Confidence: Type-Safe Prediction Objects',
    description: 'Discover how DSPy.rb\'s type-safe prediction objects catch integration errors before they reach production, giving you the confidence to ship AI features faster.',
    category: 'Features',
    author: 'Vicente Reig',
    date: 'July 15, 2025'
  },
  {
    slug: 'program-of-thought-deep-dive',
    title: 'Program of Thought: The Missing Link Between Reasoning and Code',
    description: 'Deep dive into Program of Thought (PoT) - a powerful approach that separates reasoning from computation.',
    category: 'Research',
    author: 'Vicente Reig',
    date: 'July 12, 2025'
  },
  {
    slug: 'react-agent-tutorial',
    title: 'Building ReAct Agents in Ruby: From Theory to Production',
    description: 'Learn how to build production-ready ReAct agents with DSPy.rb. Complete tutorial with code examples, best practices, and performance tips.',
    category: 'Agents',
    author: 'Vicente Reig',
    date: 'July 10, 2025'
  },
  {
    slug: 'json-parsing-reliability',
    title: 'Bulletproof JSON Parsing: How DSPy.rb Achieves 99.9% Reliability',
    description: 'Discover the 4-pattern system that makes DSPy.rb\'s JSON extraction rock-solid across all LLM providers.',
    category: 'Engineering',
    author: 'Vicente Reig',
    date: 'July 6, 2025'
  },
  {
    slug: 'ruby-idiomatic-apis',
    title: 'Idiomatic Ruby APIs for AI: Lessons from DSPy.rb',
    description: 'How to design Ruby APIs that feel natural while handling the complexity of language models. A deep dive into DSPy.rb\'s design decisions.',
    category: 'Design',
    author: 'Vicente Reig',
    date: 'July 5, 2025'
  },
  {
    slug: 'codeact-dynamic-code-generation',
    title: 'CodeAct: Dynamic Code Generation for Complex AI Tasks',
    description: 'Explore how CodeAct enables AI agents to write and execute code on-the-fly, opening new possibilities for autonomous problem-solving.',
    category: 'Agents',
    author: 'Vicente Reig',
    date: 'July 4, 2025'
  }
];

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