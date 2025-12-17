// Basic JavaScript for DSPy.rb documentation site
import Plausible from 'plausible-tracker'
import './mobile-navigation.js'

// Initialize Plausible analytics  
const plausible = Plausible({
  domain: 'oss.vicente.services',
  trackLocalhost: false,
  apiHost: 'https://plausible.io',
  hashMode: true // Enable hashed page path tracking
})

// Enable automatic page view tracking
plausible.enableAutoPageviews()

// Track outbound links
function trackOutboundLinks() {
  document.addEventListener('click', function(e) {
    const link = e.target.closest('a')
    if (!link) return
    
    const href = link.href
    if (!href) return
    
    // Check if it's an outbound link
    const currentDomain = window.location.hostname
    const linkDomain = new URL(href, window.location.origin).hostname
    
    if (linkDomain !== currentDomain && !linkDomain.includes(currentDomain)) {
      plausible.trackEvent('Outbound Link', {
        props: {
          url: href,
          text: link.textContent?.trim() || 'No text'
        }
      })
    }
  })
}

// Track file downloads
function trackFileDownloads() {
  document.addEventListener('click', function(e) {
    const link = e.target.closest('a')
    if (!link) return
    
    const href = link.href || link.getAttribute('href')
    if (!href) return
    
    // Common file extensions to track
    const fileExtensions = /\.(pdf|doc|docx|xls|xlsx|ppt|pptx|zip|rar|7z|tar|gz|mp3|mp4|avi|mov|wmv|flv|jpg|jpeg|png|gif|svg|webp|txt|csv|json|xml|yaml|yml)$/i
    
    if (fileExtensions.test(href)) {
      const filename = href.split('/').pop() || 'unknown'
      const extension = filename.split('.').pop()?.toLowerCase() || 'unknown'
      
      plausible.trackEvent('File Download', {
        props: {
          file: filename,
          type: extension,
          url: href
        }
      })
    }
  })
}

// Track 404 errors
function track404Errors() {
  // Check if current page is a 404
  if (document.title.includes('404') || 
      document.body.textContent.includes('Page not found') ||
      window.location.pathname.includes('404')) {
    plausible.trackEvent('404', {
      props: {
        path: window.location.pathname,
        referrer: document.referrer || 'Direct'
      }
    })
  }
}

// Custom event tracking helper
window.trackCustomEvent = function(eventName, properties = {}) {
  plausible.trackEvent(eventName, {
    props: properties
  })
}

// Initialize all tracking
trackOutboundLinks()
trackFileDownloads()
track404Errors()

// Add any interactive functionality here

// Add anchor links to headers for easy link copying
document.addEventListener('DOMContentLoaded', function() {
  const article = document.querySelector('article.prose');
  if (!article) return;

  const headers = article.querySelectorAll('h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]');

  headers.forEach(header => {
    const anchor = document.createElement('a');
    anchor.className = 'anchor-link';
    anchor.href = '#' + header.id;
    anchor.setAttribute('aria-label', 'Link to this section');
    anchor.textContent = '#';
    header.insertBefore(anchor, header.firstChild);
  });
});

// Smooth scrolling for anchor links
document.addEventListener('DOMContentLoaded', function() {
  const links = document.querySelectorAll('a[href^="#"]');

  links.forEach(link => {
    link.addEventListener('click', function(e) {
      const href = this.getAttribute('href');
      if (href === '#') return;

      const target = document.querySelector(href);
      if (target) {
        e.preventDefault();
        target.scrollIntoView({
          behavior: 'smooth'
        });
        // Update URL hash without jumping
        history.pushState(null, '', href);
      }
    });
  });
});
