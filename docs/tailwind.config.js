/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './src/**/*.{html,md,liquid,erb,serb,rb}',
    './frontend/**/*.js',
  ],
  theme: {
    extend: {
      colors: {
        'dspy-coral': '#f26f4e',
        'dspy-link': '#4aa885',
        'dspy-highlight': '#a8e6cf',
        'dspy-muted': '#666',
        'dspy-dark': '#111827',
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