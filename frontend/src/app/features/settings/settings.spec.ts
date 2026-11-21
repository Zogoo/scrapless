import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { provideTranslateService } from '@ngx-translate/core';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { environment } from '../../../environments/environment';
import { Fridge } from '../../core/models';
import { FridgeService } from '../../core/services/fridge.service';
import { LocaleService } from '../../core/services/locale.service';
import { SPEECH_LANG_KEY, SpeechService } from '../../core/services/speech.service';
import { Settings } from './settings';

const kitchen: Fridge = {
  id: 'k1',
  name: 'Küche',
  token: 't',
  join_code: 'j',
  locale: 'de',
  alerts_per_week: 1,
  brotbox_count: null,
  diet: null,
  excluded_foods: ['Sellerie'],
  created_at: '',
};

const noCosts = {
  mode: 'stub',
  transcribe_usd_per_minute: 0,
  totals: { calls: 0, failures: 0, usd: 0, input_tokens: 0, output_tokens: 0 },
  by_purpose: [],
  per_capture: null,
};

// Each tap saves at once (no save button), and only the field that changed.
describe('Settings, the food section', () => {
  let http: HttpTestingController;

  beforeEach(() => {
    localStorage.clear();
    // jsdom has no matchMedia; InstallService asks it whether this is the installed app.
    window.matchMedia ??= ((query: string) =>
      ({
        matches: false,
        media: query,
        addEventListener: () => undefined,
        removeEventListener: () => undefined,
      }) as unknown as MediaQueryList) as typeof window.matchMedia;
    TestBed.configureTestingModule({
      imports: [Settings],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
        provideTranslateService(),
      ],
    });
    http = TestBed.inject(HttpTestingController);
    (TestBed.inject(FridgeService) as unknown as { accept(f: Fridge): void }).accept(kitchen);
  });

  afterEach(() => TestBed.resetTestingModule());

  function render() {
    const fixture = TestBed.createComponent(Settings);
    fixture.detectChanges();
    http.match(`${environment.apiUrl}/costs`).forEach((req) => req.flush(noCosts));
    const root = fixture.nativeElement as HTMLElement;
    const group = (id: string) => [
      ...root.querySelectorAll<HTMLButtonElement>(`[aria-labelledby="${id}"] button`),
    ];
    const saved = (changes: Partial<Fridge>) => {
      const req = http.expectOne(`${environment.apiUrl}/fridge`);
      expect(req.request.method).toBe('PATCH');
      expect(req.request.body).toEqual(changes);
      req.flush({ ...kitchen, ...changes });
      fixture.detectChanges();
    };
    return { fixture, root, group, saved };
  }

  it('saves a Brotbox count, 4 for 4+, and clears it when tapped again', () => {
    const { group, saved } = render();

    group('brotbox-setting')[4].click();
    saved({ brotbox_count: 4 });
    expect(group('brotbox-setting')[4].getAttribute('aria-pressed')).toBe('true');

    group('brotbox-setting')[4].click();
    saved({ brotbox_count: null });
  });

  it('saves how the kitchen eats', () => {
    const { group, saved } = render();

    group('diet-setting')[2].click();

    saved({ diet: 'vegan' });
  });

  it('adds a quick choice to the foods to leave out, and takes it off again', () => {
    const { group, saved } = render();

    group('excluded-setting')[0].click();
    saved({ excluded_foods: ['Sellerie', 'Schwein'] });

    group('excluded-setting')[0].click();
    saved({ excluded_foods: ['Sellerie'] });
  });

  it('adds anything else typed, and removes it from its own chip', async () => {
    const { fixture, root, group, saved } = render();
    const input = root.querySelector('.add-exclusion input') as HTMLInputElement;

    input.value = ' Koriander ';
    input.dispatchEvent(new Event('input'));
    fixture.detectChanges();
    (root.querySelector('.add-exclusion button') as HTMLButtonElement).click();
    saved({ excluded_foods: ['Sellerie', 'Koriander'] });
    await fixture.whenStable(); // ngModel writes the cleared field a tick later
    expect(input.value).toBe('');

    const own = group('excluded-setting').filter((b) => b.classList.contains('own'));
    expect(own.map((b) => b.textContent!.replace('✕', '').trim())).toEqual([
      'Sellerie',
      'Koriander',
    ]);
    own[0].click();
    saved({ excluded_foods: ['Koriander'] });
  });

  it('does not add a food twice, whatever the case', () => {
    const { fixture, root } = render();
    const input = root.querySelector('.add-exclusion input') as HTMLInputElement;

    input.value = 'sellerie';
    input.dispatchEvent(new Event('input'));
    fixture.detectChanges();
    (root.querySelector('.add-exclusion button') as HTMLButtonElement).click();

    http.expectNone(`${environment.apiUrl}/fridge`);
  });
});

describe('Settings, the microphone language', () => {
  beforeEach(() => {
    localStorage.clear();
    window.matchMedia ??= ((query: string) =>
      ({
        matches: false,
        media: query,
        addEventListener: () => undefined,
        removeEventListener: () => undefined,
      }) as unknown as MediaQueryList) as typeof window.matchMedia;
    // A recogniser, so this phone counts as able to dictate.
    (window as unknown as { webkitSpeechRecognition: unknown }).webkitSpeechRecognition = class {};
    TestBed.configureTestingModule({
      imports: [Settings],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
        provideTranslateService(),
      ],
    });
  });

  afterEach(() => {
    delete (window as unknown as { webkitSpeechRecognition?: unknown }).webkitSpeechRecognition;
    TestBed.resetTestingModule();
  });

  function chips() {
    const fixture = TestBed.createComponent(Settings);
    fixture.detectChanges();
    TestBed.inject(HttpTestingController)
      .match(`${environment.apiUrl}/costs`)
      .forEach((req) => req.flush(noCosts));
    const root = fixture.nativeElement as HTMLElement;
    return {
      fixture,
      buttons: () => [
        ...root.querySelectorAll<HTMLButtonElement>('[aria-labelledby="mic-language-head"] button'),
      ],
    };
  }

  it('follows the app until a language is chosen, and "Wie die App" forgets the choice', () => {
    const { fixture, buttons } = chips();
    expect(buttons()[0].getAttribute('aria-pressed')).toBe('true'); // "Wie die App"

    buttons()[1].click();
    fixture.detectChanges();
    expect(localStorage.getItem(SPEECH_LANG_KEY)).toBe(buttons()[1].getAttribute('lang'));
    expect(buttons()[0].getAttribute('aria-pressed')).toBe('false');

    buttons()[0].click();
    fixture.detectChanges();
    expect(localStorage.getItem(SPEECH_LANG_KEY)).toBeNull();
    expect(TestBed.inject(SpeechService).speechLang()).toBe(
      TestBed.inject(LocaleService).current(),
    );
  });
});
