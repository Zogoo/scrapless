import { describe, expect, it } from 'vitest';

import { qrImageSrc } from './qr-image';

describe('qrImageSrc', () => {
  it('renders the share link as an SVG image', () => {
    const src = qrImageSrc('https://scrapless.test/join#join-code');

    expect(src.startsWith('data:image/svg+xml')).toBe(true);
    const svg = decodeURIComponent(src);
    expect(svg).toContain('<svg');
    expect(svg).toContain('</svg>');
  });
});
