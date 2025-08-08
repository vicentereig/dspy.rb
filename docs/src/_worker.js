export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    
    // Redirect root to /dspy.rb/
    if (url.pathname === '/' || url.pathname === '') {
      return Response.redirect(`${url.origin}/dspy.rb/`, 301);
    }
    
    // Handle /dspy.rb paths
    if (url.pathname.startsWith('/dspy.rb')) {
      // Remove /dspy.rb prefix for asset fetching
      const assetPath = url.pathname.slice(7) || '/';
      
      // Create new URL with stripped path
      const assetUrl = new URL(request.url);
      assetUrl.pathname = assetPath;
      
      // Fetch the asset from Pages
      const response = await env.ASSETS.fetch(assetUrl);
      
      // If HTML, rewrite links to include /dspy.rb prefix
      if (response.headers.get('content-type')?.includes('text/html')) {
        let html = await response.text();
        
        // Rewrite absolute paths to include /dspy.rb
        html = html.replace(/href="\//g, 'href="/dspy.rb/');
        html = html.replace(/src="\//g, 'src="/dspy.rb/');
        html = html.replace(/action="\//g, 'action="/dspy.rb/');
        
        // Fix asset paths that shouldn't have /dspy.rb
        html = html.replace(/\/dspy\.rb\/_bridgetown/g, '/_bridgetown');
        
        return new Response(html, {
          status: response.status,
          headers: response.headers
        });
      }
      
      return response;
    }
    
    // For paths not starting with /dspy.rb, return 404
    return new Response('Not Found', { status: 404 });
  }
};