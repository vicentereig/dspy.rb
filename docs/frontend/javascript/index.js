// Basic JavaScript for DSPy.rb documentation site
import Plausible from 'plausible-tracker'

// Initialize Plausible analytics  
const plausible = Plausible({
  domain: 'vicentereig.github.io',
  trackLocalhost: false,
  apiHost: 'https://plausible.io'
})

// Enable automatic page view tracking
plausible.enableAutoPageviews()

// Add debugging for Plausible
console.log('Plausible Analytics initialized for domain:', 'vicentereig.github.io')
console.log('Current location:', {
  hostname: location.hostname,
  href: location.href,
  protocol: location.protocol
})

// Manual tracking test (you can check network tab for this)
plausible.trackEvent('Test Event', { props: { source: 'manual' } })

// Add any interactive functionality here
console.log('DSPy.rb documentation site loaded');

// Example: Smooth scrolling for anchor links
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
      }
    });
  });
});
