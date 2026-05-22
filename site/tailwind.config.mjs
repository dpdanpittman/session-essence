/** @type {import('tailwindcss').Config} */
export default {
  content: ['./src/**/*.{astro,html,js,jsx,md,mdx,ts,tsx}'],
  theme: {
    extend: {
      colors: {
        bg: '#0d0c0e',
        panel: '#15131a',
        'panel-2': '#1c1a23',
        border: '#2a2530',
        ink: '#e9e4dd',
        'ink-dim': '#a39e96',
        muted: '#6e6770',
        accent: '#d97757',
        'accent-dim': '#b8634a',
        'accent-soft': '#3a221c',
        ember: '#e8a87c',
        cool: '#7aa2c8',
      },
      fontFamily: {
        display: ['Newsreader', 'Cormorant Garamond', 'Georgia', 'serif'],
        body: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'SF Mono', 'Menlo', 'Consolas', 'monospace'],
      },
      animation: {
        breathe: 'breathe 8s ease-in-out infinite',
      },
      keyframes: {
        breathe: {
          '0%, 100%': { opacity: '0.65' },
          '50%': { opacity: '1' },
        },
      },
    },
  },
  plugins: [],
};
