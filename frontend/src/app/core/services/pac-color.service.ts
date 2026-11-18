import { Injectable, signal } from '@angular/core';

/** Solid bodies the dark pupil still reads on. Yellow is the classic default. */
export const PAC_COLORS = [
  { id: 'yellow', hex: '#ffcc00' },
  { id: 'orange', hex: '#ffb300' },
  { id: 'coral', hex: '#ff8a65' },
  { id: 'sky', hex: '#4fc3f7' },
] as const;

const PAC_KEY = 'scrapless_pac';
const PAC_DEFAULT = PAC_COLORS[0].hex;

/**
 * The slider thumb's colour, remembered on this phone the same way the
 * language is. Not a household setting: another phone keeps its own.
 */
@Injectable({ providedIn: 'root' })
export class PacColorService {
  readonly choices = PAC_COLORS;
  readonly color = signal(readPacColor());

  use(id: string): void {
    const found = PAC_COLORS.find((choice) => choice.id === id);
    if (!found) return;

    this.color.set(found.hex);
    try {
      localStorage.setItem(PAC_KEY, found.id);
    } catch {
      /* private mode: the choice lasts for this visit */
    }
  }
}

function readPacColor(): string {
  try {
    const saved = localStorage.getItem(PAC_KEY);
    return PAC_COLORS.find((choice) => choice.id === saved)?.hex ?? PAC_DEFAULT;
  } catch {
    return PAC_DEFAULT;
  }
}
