/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './src/**/*.{html,md,liquid,erb,serb,rb}',
    './frontend/**/*.js',
  ],
  theme: {
    extend: {
      colors: {
        // Mapped onto the OKLCH design tokens (see design.md / tokens.css)
        'dspy-coral': 'var(--color-accent)',
        'dspy-link': 'var(--color-link)',
        'dspy-highlight': 'var(--color-highlight)',
        'dspy-muted': 'var(--color-ink-3)',
        'dspy-dark': 'var(--color-ink)',
        // Editorial surface + ink scale
        'paper': 'var(--color-paper)',
        'paper-2': 'var(--color-paper-2)',
        'ink': 'var(--color-ink)',
        'ink-2': 'var(--color-ink-2)',
        'ink-3': 'var(--color-ink-3)',
        'rule': 'var(--color-rule)',
      },
      fontFamily: {
        'serif': ['Newsreader', 'Georgia', 'serif'],
        'sans': ['Manrope', 'system-ui', 'sans-serif'],
        'mono': ['JetBrains Mono', 'Fira Code', 'Consolas', 'Monaco', 'monospace'],
      },
      typography: (theme) => ({
        DEFAULT: {
          css: {
            code: {
              backgroundColor: theme('colors.gray.100'),
              padding: '0.125rem 0.25rem',
              borderRadius: '0.25rem',
              fontWeight: '500',
              '&::before': {
                content: '""',
              },
              '&::after': {
                content: '""',
              },
            },
            'code::before': {
              content: '""',
            },
            'code::after': {
              content: '""',
            },
            pre: {
              backgroundColor: theme('colors.gray.900'),
              color: theme('colors.gray.100'),
              overflowX: 'auto',
              borderColor: theme('colors.gray.700'),
            },
            'pre code': {
              backgroundColor: 'transparent',
              borderWidth: '0',
              borderRadius: '0',
              padding: '0',
              fontWeight: 'inherit',
              color: theme('colors.gray.100'),
              fontSize: 'inherit',
              fontFamily: 'inherit',
              lineHeight: 'inherit',
            },
            'pre code::before': {
              content: '""',
            },
            'pre code::after': {
              content: '""',
            },
          },
        },
      }),
    },
  },
  plugins: [
    require('@tailwindcss/typography'),
    require('@tailwindcss/forms'),
  ],
}