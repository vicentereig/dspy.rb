// Mobile Navigation Handler
document.addEventListener('DOMContentLoaded', function() {
  // Get elements
  const menuButton = document.querySelector('nav button[type="button"]');
  const mobileMenu = document.getElementById('mobile-menu');
  const closeButton = document.getElementById('mobile-menu-close');
  
  if (!menuButton || !mobileMenu) return;

  // Toggle menu function
  function toggleMenu(show) {
    if (show) {
      mobileMenu.classList.remove('hidden');
      document.body.classList.add('overflow-hidden');
    } else {
      mobileMenu.classList.add('hidden');
      document.body.classList.remove('overflow-hidden');
    }
  }

  // Event listeners
  menuButton.addEventListener('click', () => toggleMenu(true));
  
  if (closeButton) {
    closeButton.addEventListener('click', () => toggleMenu(false));
  }

  // Close on escape key
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !mobileMenu.classList.contains('hidden')) {
      toggleMenu(false);
    }
  });

  // Close when clicking outside
  mobileMenu.addEventListener('click', (e) => {
    if (e.target === mobileMenu || e.target === mobileMenu.firstElementChild) {
      toggleMenu(false);
    }
  });
});