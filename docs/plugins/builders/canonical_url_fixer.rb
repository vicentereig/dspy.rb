class Builders::CanonicalUrlFixer < SiteBuilder
  def build
    hook :site, :pre_render do |site|
      # Fix canonical URLs for all pages
      if site.collections.pages&.resources
        site.collections.pages.resources.each do |page|
          fix_canonical_url(page)
        end
      end
      
      # Fix canonical URLs for articles
      articles = site.collections.articles&.resources || []
      articles.each do |article|
        fix_canonical_url(article)
      end
      
      # Fix canonical URLs for other collections
      site.collections.each do |name, collection|
        next if name == :pages || name == :articles # already handled above
        collection.resources.each do |resource|
          fix_canonical_url(resource)
        end
      end
    end
  end
  
  private
  
  def fix_canonical_url(page)
    # Only set canonical_url if it's not already explicitly set
    unless page.data["canonical_url"]
      # Get the page URL - try different methods to find it
      page_url = page.data["url"] || 
                 page.data["relative_url"] || 
                 (page.respond_to?(:url) ? page.url : "") ||
                 (page.respond_to?(:relative_url) ? page.relative_url : "")
      
      # Clean up the URL (remove index.html, ensure proper format)
      page_url = page_url.to_s.gsub(/\/index\.html$/, "/")
      page_url = "/" if page_url.empty? || page_url == "/index.html"
      
      # Use the full URL from site metadata
      canonical_url = "https://vicentereig.github.io/dspy.rb#{page_url}"
      page.data["canonical_url"] = canonical_url
    end
  end
end