require "fileutils"
require "playwright"

class Builders::OgImageGenerator < SiteBuilder
    def build
      Bridgetown.logger.info "OG Images:", "Plugin loaded!"
      
      hook :site, :post_write do |site|
        # Only generate OG images in production or if explicitly enabled
        next unless site.config["environment"] == "production" || ENV["GENERATE_OG_IMAGES"] == "true"
        
        # Generate OG images for articles and default
        begin
          Bridgetown.logger.info "OG Images:", "Starting Open Graph image generation"
          
          # Ensure output directory exists
          og_output_dir = File.join(site.config.destination, "images", "og")
          Bridgetown.logger.info "OG Images:", "Output directory: #{og_output_dir}"
          FileUtils.mkdir_p(og_output_dir)
          
          # Generate default OG image first
          generate_default_og_image(og_output_dir)
          
          # Get articles collection
          articles = site.collections.articles&.resources || []
          
          if articles.any?
            Bridgetown.logger.info "OG Images:", "Generating images for #{articles.length} articles"
            
            # Generate images using Playwright
            generate_all_images(articles, og_output_dir)
            
            Bridgetown.logger.info "OG Images:", "Generation complete!"
          else
            Bridgetown.logger.warn "OG Images:", "No articles found to generate images for"
          end
        rescue => e
          Bridgetown.logger.error "OG Images:", "Error during generation: #{e.message}"
          Bridgetown.logger.error "OG Images:", e.backtrace.join("\n")
        end
      end
    end

    private

    def generate_all_images(articles, output_dir)
      Playwright.create(playwright_cli_executable_path: './node_modules/.bin/playwright') do |playwright|
        chromium = playwright.chromium
        browser = chromium.launch(headless: true, timeout: 30000)
        
        begin
          # Create a single page to reuse for all images
          page = browser.new_page
          page.set_viewport_size(width: 1200, height: 630)
          
          articles.each do |article|
            generate_single_image(page, article, output_dir)
          end
        ensure
          browser.close
        end
      end
    rescue => e
      Bridgetown.logger.error "OG Images:", "Failed to launch Playwright: #{e.message}"
      Bridgetown.logger.error "OG Images:", "Make sure Playwright is installed: npx playwright install chromium"
    end

    def generate_single_image(page, article, output_dir)
      # Generate a unique filename based on the article slug
      slug = article.data.slug || article.basename_without_ext
      output_path = File.join(output_dir, "#{slug}.png")
      
      # Skip if image already exists and is newer than the article
      if File.exist?(output_path) && File.mtime(output_path) > article.mtime
        Bridgetown.logger.info "OG Images:", "Skipping #{slug} (already exists)"
        return
      end
      
      # Generate HTML content for the OG image
      html_content = generate_og_html(article)
      
      # Load the HTML content
      page.set_content(html_content, timeout: 30000)
      
      # Wait for any fonts to load
      sleep(0.2)
      
      # Take screenshot
      page.screenshot(path: output_path)
      
      Bridgetown.logger.info "OG Images:", "Generated image for #{slug}"
    rescue => e
      Bridgetown.logger.error "OG Images:", "Error generating image for #{article.data.title}: #{e.message}"
    end

    def generate_og_html(article)
      # Extract data from the article
      title = article.data.title || "Untitled"
      description = article.data.description || ""
      author = article.data.author || "Vicente Reig"
      date = article.data.date ? format_date(article.data.date) : ""
      category = article.data.category || "Article"
      reading_time = article.data.reading_time || calculate_reading_time(article)
      
      # Escape HTML entities
      title = CGI.escapeHTML(title)
      description = CGI.escapeHTML(description)
      author = CGI.escapeHTML(author)
      
      <<~HTML
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
            
            .decorative-circles {
              position: absolute;
              bottom: -100px;
              left: -100px;
              width: 300px;
              height: 300px;
              background: radial-gradient(circle, rgba(255,255,255,0.05) 0%, transparent 70%);
              border-radius: 50%;
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
            
            .reading-time {
              font-size: 16px;
              opacity: 0.8;
              font-weight: 400;
            }
            
            .content {
              flex: 1;
              display: flex;
              flex-direction: column;
              justify-content: center;
            }
            
            .title {
              font-size: #{title.length > 50 ? '64px' : '72px'};
              font-weight: 800;
              line-height: 1.1;
              margin-bottom: 24px;
              text-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
              letter-spacing: -0.02em;
            }
            
            .description {
              font-size: 28px;
              line-height: 1.4;
              opacity: 0.9;
              font-weight: 300;
              max-width: 900px;
              text-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
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
          <div class="decorative-circles"></div>
          <div class="container">
            <div class="header">
              <div class="category-badge">#{category}</div>
              #{reading_time.empty? ? '' : '<div class="reading-time">' + reading_time + '</div>'}
            </div>
            
            <div class="content">
              <h1 class="title">#{title}</h1>
              #{description.empty? ? '' : '<p class="description">' + description + '</p>'}
            </div>
            
            <div class="footer">
              <div class="author-info">
                <div class="author-avatar">#{author[0].upcase}</div>
                <div class="author-details">
                  <div class="author-name">#{author}</div>
                  #{date.empty? ? '' : '<div class="publish-date">' + date + '</div>'}
                </div>
              </div>
              <div class="branding">
                <div class="ruby-icon">💎</div>
                <span>DSPy.rb</span>
              </div>
            </div>
          </div>
        </body>
        </html>
      HTML
    end

    def format_date(date)
      return "" unless date
      
      if date.respond_to?(:strftime)
        date.strftime("%B %d, %Y")
      else
        date.to_s
      end
    end

    def calculate_reading_time(article)
      # If content is available, calculate reading time
      if article.content
        word_count = article.content.split.size
        minutes = (word_count / 200.0).ceil
        "#{minutes} min read"
      else
        ""
      end
    end

    def generate_default_og_image(output_dir)
      Playwright.create(playwright_cli_executable_path: './node_modules/.bin/playwright') do |playwright|
        chromium = playwright.chromium
        browser = chromium.launch(headless: true, timeout: 30000)
        
        begin
          page = browser.new_page
          page.set_viewport_size(width: 1200, height: 630)
          
          html_content = <<~HTML
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
          HTML
          
          page.set_content(html_content, timeout: 30000)
          sleep(0.2)
          page.screenshot(path: File.join(output_dir, "default.png"))
          
          Bridgetown.logger.info "OG Images:", "Generated default OG image"
        ensure
          browser.close
        end
      end
    end
end