// Mobile Table of Contents Integration
import { generateTableOfContents, initTocHighlighting } from './table-of-contents.js';

export function initMobileTOC() {
  // Check if we're on a documentation page
  const article = document.querySelector('article.prose');
  if (!article) return;

  // Generate TOC
  const toc = generateTableOfContents();
  if (!toc) return;

  // Create mobile TOC container
  const mobileTocContainer = document.createElement('div');
  mobileTocContainer.className = 'mobile-toc';
  mobileTocContainer.innerHTML = `
    <button class="mobile-toc-toggle" aria-expanded="false" aria-controls="mobile-toc-content">
      <span>Table of Contents</span>
      <svg class="w-5 h-5 transition-transform duration-200" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
      </svg>
    </button>
    <div id="mobile-toc-content" class="mobile-toc-content">
      <div class="pt-4"></div>
    </div>
  `;

  // Add TOC to container
  const contentDiv = mobileTocContainer.querySelector('.pt-4');
  contentDiv.appendChild(toc);

  // Insert before first H2 or at the beginning of article
  const firstHeading = article.querySelector('h2');
  if (firstHeading) {
    firstHeading.parentNode.insertBefore(mobileTocContainer, firstHeading);
  } else {
    article.insertBefore(mobileTocContainer, article.firstChild);
  }

  // Toggle functionality
  const toggleButton = mobileTocContainer.querySelector('.mobile-toc-toggle');
  const toggleIcon = toggleButton.querySelector('svg');
  const content = mobileTocContainer.querySelector('.mobile-toc-content');

  toggleButton.addEventListener('click', () => {
    const isExpanded = toggleButton.getAttribute('aria-expanded') === 'true';
    toggleButton.setAttribute('aria-expanded', !isExpanded);
    toggleIcon.classList.toggle('rotate-180');
    content.classList.toggle('expanded');
  });

  // Close TOC when clicking a link
  const tocLinks = mobileTocContainer.querySelectorAll('a');
  tocLinks.forEach(link => {
    link.addEventListener('click', () => {
      toggleButton.setAttribute('aria-expanded', 'false');
      toggleIcon.classList.remove('rotate-180');
      content.classList.remove('expanded');
    });
  });

  // Initialize highlighting
  initTocHighlighting();
}

// Initialize on DOM ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initMobileTOC);
} else {
  initMobileTOC();
}