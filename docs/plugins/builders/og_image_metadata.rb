class Builders::OgImageMetadata < SiteBuilder
  def build
    hook :site, :pre_render do |site|
      # Add OG image paths to articles
      articles = site.collections.articles&.resources || []
      
      articles.each do |article|
        # Generate the OG image path based on the article slug
        slug = article.data.slug || article.basename_without_ext
        og_image_path = "/images/og/#{slug}.png"
        
        # Set the image in the article's data
        article.data.image ||= {}
        article.data.image = {
          "path" => og_image_path,
          "width" => 1200,
          "height" => 630
        }
      end
      
      # Add OG image paths to documentation pages
      if site.collections.pages&.resources
        pages_resources = site.collections.pages.resources
        doc_pages = pages_resources.select { |page| 
          path = if page.respond_to?(:relative_path)
                   page.relative_path.to_s
                 elsif page.respond_to?(:path)
                   page.path.to_s
                 else
                   ''
                 end
          is_doc_page = path.end_with?('.md') && 
                       !path.start_with?('_articles/') &&
                       !path.start_with?('blog/') &&
                       path != 'index.md' &&
                       (path.start_with?('advanced/') || path.start_with?('core-concepts/') || 
                        path.start_with?('getting-started/') || path.start_with?('optimization/') || 
                        path.start_with?('production/'))
          is_doc_page
        }
        
        doc_pages.each do |page|
          # Generate the OG image path based on the page path
          page_path = if page.respond_to?(:relative_path)
                        page.relative_path.to_s
                      elsif page.respond_to?(:path)
                        page.path.to_s
                      else
                        ''
                      end
          slug = page_path.gsub('src/', '').gsub('.md', '').gsub('/', '-')
          og_image_path = "/images/og/#{slug}.png"
          
          # Set the image in the page's data
          page.data.image ||= {}
          page.data.image = {
            "path" => og_image_path,
            "width" => 1200,
            "height" => 630
          }
        end
      end
    end
  end
end