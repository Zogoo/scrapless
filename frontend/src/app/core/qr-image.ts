import { renderSVG } from 'uqr';

/** A scannable QR code as an image src. Black on white, so a camera can read it. */
export function qrImageSrc(text: string): string {
  const svg = renderSVG(text, {
    ecc: 'M',
    border: 2,
    pixelSize: 8,
    blackColor: '#1b1b1f',
    whiteColor: '#ffffff',
  });

  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
}
