// Mobile Navigation Handler with Animations
document.addEventListener('DOMContentLoaded', function() {
  // Get elements
  const menuButton = document.getElementById('mobile-menu-button');
  const mobileMenu = document.getElementById('mobile-menu');
  const closeButton = document.getElementById('mobile-menu-close');
  const backdrop = document.getElementById('mobile-menu-backdrop');
  const menuPanel = mobileMenu?.querySelector('.relative.mr-16');
  
  if (!menuButton || !mobileMenu) return;

  // Toggle menu function with animations
  function toggleMenu(show) {
    if (show) {
      // Show menu with animation
      mobileMenu.classList.remove('hidden');
      document.body.classList.add('overflow-hidden');
      menuButton.setAttribute('aria-expanded', 'true');
      
      // Trigger animations after display change
      requestAnimationFrame(() => {
        mobileMenu.classList.add('menu-open');
        if (backdrop) backdrop.classList.add('backdrop-visible');
        if (menuPanel) menuPanel.classList.add('panel-visible');
      });
    } else {
      // Hide menu with animation
      menuButton.setAttribute('aria-expanded', 'false');
      mobileMenu.classList.remove('menu-open');
      if (backdrop) backdrop.classList.remove('backdrop-visible');
      if (menuPanel) menuPanel.classList.remove('panel-visible');
      
      // Hide after animation completes
      setTimeout(() => {
        mobileMenu.classList.add('hidden');
        document.body.classList.remove('overflow-hidden');
      }, 300);
    }
  }

  // Event listeners
  menuButton.addEventListener('click', () => toggleMenu(true));
  
  if (closeButton) {
    closeButton.addEventListener('click', () => toggleMenu(false));
  }

  if (backdrop) {
    backdrop.addEventListener('click', () => toggleMenu(false));
  }

  // Close on escape key
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !mobileMenu.classList.contains('hidden')) {
      toggleMenu(false);
    }
  });

  // Dropdown toggles for both desktop and mobile
  const dropdownButtons = document.querySelectorAll('[data-dropdown-toggle]');
  dropdownButtons.forEach(button => {
    button.addEventListener('click', () => {
      const isExpanded = button.getAttribute('aria-expanded') === 'true';
      button.setAttribute('aria-expanded', !isExpanded);
      
      const icon = button.querySelector('svg');
      if (icon) {
        icon.classList.toggle('rotate-90');
      }
      
      const targetId = button.getAttribute('data-dropdown-toggle');
      const target = document.getElementById(targetId);
      if (target) {
        target.classList.toggle('hidden');
      }
    });
  });

  // Animated hamburger icon
  const hamburgerIcon = menuButton.querySelector('svg');
  if (hamburgerIcon) {
    // Create animated hamburger structure
    hamburgerIcon.innerHTML = `
      <g class="hamburger-lines">
        <path class="line-top" stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5" />
        <path class="line-middle" stroke-linecap="round" stroke-linejoin="round" d="M3.75 12h16.5" />
        <path class="line-bottom" stroke-linecap="round" stroke-linejoin="round" d="M3.75 17.25h16.5" />
      </g>
    `;
  }

  // Update hamburger animation on menu state change
  const observer = new MutationObserver(() => {
    const isOpen = menuButton.getAttribute('aria-expanded') === 'true';
    if (hamburgerIcon) {
      if (isOpen) {
        hamburgerIcon.classList.add('menu-icon-open');
      } else {
        hamburgerIcon.classList.remove('menu-icon-open');
      }
    }
  });

  observer.observe(menuButton, { attributes: true, attributeFilter: ['aria-expanded'] });
});