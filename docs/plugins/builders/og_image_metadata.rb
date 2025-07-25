class Builders::OgImageMetadata < SiteBuilder
  def build
    hook :site, :pre_render do |site|
      # Add OG image paths to articles
      articles = site.collections.articles&.resources || []
      
      articles.each do |article|
        # Generate the OG image path based on the article slug
        slug = article.data.slug || article.basename_without_ext
        
        # Include base_path for production builds (e.g., GitHub Pages)
        base_path = site.config["base_path"] || ""
        og_image_path = "#{base_path}/images/og/#{slug}.png"
        
        # Set the image in the article's data
        article.data.image ||= {}
        article.data.image = {
          "path" => og_image_path,
          "width" => 1200,
          "height" => 630
        }
      end
    end
  end
end