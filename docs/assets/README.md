# macfuseGui Marketing Site Assets

This directory contains the static assets for the `macfuseGui` marketing website hosted on GitHub Pages.

## File Structure

- `site.css`: Custom styles for glassmorphism, gradients, and specific visual tweaks that extend Tailwind.
- `site.js`: Logic for:
  - Theme toggling (Dark/Light) with `localStorage` persistence.
  - Dynamic GitHub repo links (configured via `const REPO`).
  - FAQ accordion behavior (ARIA-compliant).
  - Copyright year auto-update.
- `hero-bg.webp`: Local hero background image (Unsplash source, converted to WebP for performance).
- `og-image.webp`: Social preview image in WebP format.

## Configuration

To change the target repository for download/GitHub links, edit `site.js`:

```javascript
const REPO = "ripplethor/macfuseGUI";
```

## Theme System

The theme system uses a pre-paint script in `index.html` to prevent flashing. It checks `localStorage` first, then system preference.
State is toggled via the button with `id="theme-toggle"`.

## Development

The site is built with Tailwind CSS v4 via CDN for simplicity and no-build deployment.
All paths must be **relative** (e.g., `assets/site.css`, not `/assets/site.css`) to ensure compatibility with GitHub Pages subdirectory hosting (`/macfuseGui/`).

## Deployment

1. Commit changes to `main`.
2. Go to repository Settings -> Pages.
3. Select Source: `Deploy from a branch`.
4. Branch: `main`, Folder: `/docs`.
5. Save.
