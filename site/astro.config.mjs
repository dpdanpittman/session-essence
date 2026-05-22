import { defineConfig } from 'astro/config';
import tailwind from '@astrojs/tailwind';

export default defineConfig({
  base: '/essence',
  integrations: [tailwind()],
  output: 'static',
});
