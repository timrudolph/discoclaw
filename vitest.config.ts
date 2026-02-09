import { configDefaults, defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // Keep tests independent of local-only symlinks (legacy workspace, content/workspace exports, etc).
    // Vitest can hit ELOOP when scanning symlinked trees.
    exclude: [
      ...configDefaults.exclude,
      'legacy/**',
      'workspace/**',
      'exports/**',
      'content/**',
      'var/**',
    ],
  },
});

