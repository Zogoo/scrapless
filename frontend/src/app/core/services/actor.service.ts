import { Injectable, signal } from '@angular/core';

/** A display name on this phone. Not an account, and not sent anywhere until an add. */
export const ACTOR_NAME_LIMIT = 40;
const ACTOR_KEY = 'scrapless_actor';

export function cleanActorName(value: string): string {
  return value
    .replace(/[\u0000-\u001F\u007F]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, ACTOR_NAME_LIMIT);
}

@Injectable({ providedIn: 'root' })
export class ActorService {
  readonly name = signal(readActorName());

  setName(value: string): void {
    const cleaned = cleanActorName(value);
    this.name.set(cleaned);

    try {
      if (cleaned) localStorage.setItem(ACTOR_KEY, cleaned);
      else localStorage.removeItem(ACTOR_KEY);
    } catch {
      // Private mode. The name still applies for this session, via the signal.
    }
  }
}

function readActorName(): string {
  try {
    return cleanActorName(localStorage.getItem(ACTOR_KEY) ?? '');
  } catch {
    return '';
  }
}
