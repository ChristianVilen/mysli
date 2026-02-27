import { defineConfig } from 'astro/config';
import tailwind from '@astrojs/tailwind';

export default defineConfig({
  site: 'https://christianvilen.github.io',
  base: '/ku-ka',
  integrations: [tailwind()],
});
