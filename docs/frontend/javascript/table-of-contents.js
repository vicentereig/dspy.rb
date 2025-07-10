// Table of Contents Generator
export function generateTableOfContents() {
  // Find the article content
  const article = document.querySelector('article.prose');
  if (!article) return null;

  // Get all headings
  const headings = article.querySelectorAll('h2, h3, h4');
  if (headings.length === 0) return null;

  // Create TOC structure
  const toc = document.createElement('nav');
  toc.className = 'toc-navigation';
  toc.setAttribute('aria-label', 'Table of contents');

  const tocList = document.createElement('ul');
  tocList.className = 'space-y-1';

  let currentLevel = 2;
  let currentList = tocList;
  const listStack = [tocList];

  headings.forEach((heading) => {
    // Ensure heading has an ID for anchoring
    if (!heading.id) {
      heading.id = heading.textContent
        .toLowerCase()
        .replace(/[^\w\s-]/g, '')
        .replace(/\s+/g, '-')
        .trim();
    }

    const level = parseInt(heading.tagName.charAt(1));
    
    // Adjust nesting level
    while (level > currentLevel && listStack.length < 3) {
      const newList = document.createElement('ul');
      newList.className = 'ml-4 mt-1 space-y-1';
      
      if (currentList.lastElementChild) {
        currentList.lastElementChild.appendChild(newList);
      } else {
        currentList.appendChild(newList);
      }
      
      listStack.push(newList);
      currentList = newList;
      currentLevel++;
    }
    
    while (level < currentLevel && listStack.length > 1) {
      listStack.pop();
      currentList = listStack[listStack.length - 1];
      currentLevel--;
    }

    // Create TOC item
    const listItem = document.createElement('li');
    const link = document.createElement('a');
    
    link.href = `#${heading.id}`;
    link.textContent = heading.textContent;
    link.className = `block rounded-md px-3 py-1 text-sm ${
      level === 2 
        ? 'font-medium text-gray-900 hover:bg-gray-100' 
        : 'text-gray-700 hover:bg-gray-50'
    }`;
    
    // Smooth scroll behavior
    link.addEventListener('click', (e) => {
      e.preventDefault();
      heading.scrollIntoView({ behavior: 'smooth', block: 'start' });
      
      // Update URL without page jump
      history.pushState(null, null, `#${heading.id}`);
      
      // Close mobile menu if open
      const mobileMenu = document.getElementById('mobile-menu');
      if (mobileMenu && !mobileMenu.classList.contains('hidden')) {
        mobileMenu.classList.add('hidden');
        document.body.classList.remove('overflow-hidden');
      }
    });

    listItem.appendChild(link);
    currentList.appendChild(listItem);
  });

  toc.appendChild(tocList);
  return toc;
}

// Highlight current section in TOC
export function initTocHighlighting() {
  const headings = document.querySelectorAll('article h2, article h3, article h4');
  const tocLinks = document.querySelectorAll('.toc-navigation a');
  
  if (headings.length === 0 || tocLinks.length === 0) return;

  // Create intersection observer
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          // Remove all active classes
          tocLinks.forEach(link => {
            link.classList.remove('bg-gray-100', 'text-dspy-ruby');
          });
          
          // Add active class to current section
          const activeLink = document.querySelector(`.toc-navigation a[href="#${entry.target.id}"]`);
          if (activeLink) {
            activeLink.classList.add('bg-gray-100', 'text-dspy-ruby');
          }
        }
      });
    },
    {
      rootMargin: '-20% 0% -70% 0%',
      threshold: 0
    }
  );

  // Observe all headings
  headings.forEach(heading => observer.observe(heading));
}