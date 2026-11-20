import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { provideTranslateService } from '@ngx-translate/core';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { environment } from '../../../environments/environment';
import { ScoredItem, Today } from '../../core/models';
import { ItemsService } from '../../core/services/items.service';
import { UndoService } from '../../core/services/undo.service';
import { Kitchen } from './kitchen';

function pack(
  id: number,
  name: string,
  amountLeft = 1,
  openedOn: string | null = null,
  phase: ScoredItem['phase'] = 'fresh',
): ScoredItem {
  return {
    id,
    display_name: name,
    canonical_name: name.toLowerCase(),
    storage: 'fridge',
    amount_left: amountLeft,
    window_start: '2026-11-14',
    window_end: '2026-11-20',
    opened_on: openedOn,
    phase,
    headline: 'still good',
    safety_date: false,
    high_risk: false,
  } as ScoredItem;
}

function today(items: ScoredItem[]): Today {
  return {
    use_first: items,
    fine_for_now: [],
    probably_gone: [],
    sweep_count: 0,
    as_of: '2026-11-18',
    has_captured: true,
  };
}

function showing(root: ParentNode): string[] {
  return [...root.querySelectorAll('li:not(.leaving) .summary .name')].map(
    (name) => name.textContent?.trim() ?? '',
  );
}

function openFirst(root: ParentNode): void {
  const toggle = root.querySelector('.toggle') as HTMLButtonElement | null;
  toggle?.click();
}

describe('Kitchen', () => {
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [Kitchen],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
        provideTranslateService(),
      ],
    });
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    TestBed.resetTestingModule();
  });

  it('drops the card and shows Used up when the slider is released at 0%', () => {
    const fixture = TestBed.createComponent(Kitchen);
    fixture.detectChanges();
    const pasta = pack(1, 'Pasta');
    const milk = pack(2, 'Milk');
    http.expectOne(`${environment.apiUrl}/items`).flush(today([pasta, milk]));
    fixture.detectChanges();
    expect(showing(fixture.nativeElement)).toEqual(['Pasta', 'Milk']);
    openFirst(fixture.nativeElement);
    fixture.detectChanges();

    const items = TestBed.inject(ItemsService);
    items.load().subscribe();
    const stale = http.expectOne(`${environment.apiUrl}/items`);

    const slider = fixture.nativeElement.querySelector('input.level') as HTMLInputElement;
    slider.value = '0';
    slider.dispatchEvent(new Event('pointerup'));
    fixture.detectChanges();

    expect(TestBed.inject(UndoService).notice()?.message).toBe('undo.used_up');
    expect(TestBed.inject(UndoService).notice()?.itemIds).toEqual([1]);
    expect(showing(fixture.nativeElement)).toEqual(['Milk']);

    stale.flush(today([pasta, milk]));
    fixture.detectChanges();
    expect(showing(fixture.nativeElement)).toEqual(['Milk']);

    http.expectOne(`${environment.apiUrl}/items/1/resolve`).flush({});
    http.expectOne(`${environment.apiUrl}/items/1/revert_open`).flush({});
    http.expectOne(`${environment.apiUrl}/items/level`).flush({ items: [] });
    http
      .expectOne(`${environment.apiUrl}/items`)
      .flush(today([{ ...pasta, amount_left: 0 }, milk]));
    fixture.detectChanges();

    expect(showing(fixture.nativeElement)).toEqual(['Milk']);
  });

  it('switches the thumb to the closed radish when an opened pack is restored', () => {
    const fixture = TestBed.createComponent(Kitchen);
    fixture.detectChanges();
    const potato = pack(1, 'Potato', 0.5, '2026-11-17', 'aging');
    http.expectOne(`${environment.apiUrl}/items`).flush(today([potato]));
    fixture.detectChanges();
    openFirst(fixture.nativeElement);
    fixture.detectChanges();

    const root = fixture.nativeElement as HTMLElement;
    expect(root.querySelector('.bite img')?.getAttribute('src')).toBe(
      '/branding/rettich/mascot/rettich-soon-opened-light.svg',
    );

    const slider = root.querySelector('input.level') as HTMLInputElement;
    slider.value = '100';
    slider.dispatchEvent(new Event('input'));
    slider.dispatchEvent(new Event('pointerup'));

    // The reply still says open. The list that comes back does not.
    http.expectNone(`${environment.apiUrl}/items/1/resolve`);
    http.expectOne(`${environment.apiUrl}/items/1/revert_open`).flush({ opened_on: '2026-11-17' });
    http.expectOne(`${environment.apiUrl}/items/level`).flush({ items: [] });
    http
      .expectOne(`${environment.apiUrl}/items`)
      .flush(today([pack(1, 'Potato', 1, null, 'fresh')]));
    fixture.detectChanges();

    expect(root.querySelector('.bite img')?.getAttribute('src')).toBe(
      '/branding/rettich/mascot/rettich-fresh-light.svg',
    );
  });

  // Nothing on a card shows it can be swiped, so the list says it once.
  describe('the swipe hint', () => {
    function load(): {
      fixture: ReturnType<typeof TestBed.createComponent<Kitchen>>;
      root: HTMLElement;
    } {
      const fixture = TestBed.createComponent(Kitchen);
      fixture.detectChanges();
      http.expectOne(`${environment.apiUrl}/items`).flush(today([pack(1, 'Milk')]));
      fixture.detectChanges();
      return { fixture, root: fixture.nativeElement as HTMLElement };
    }

    beforeEach(() => localStorage.clear());

    it('shows above the list until a swipe reaches the delete question, then stays gone', () => {
      const { fixture, root } = load();
      expect(root.querySelector('.swipe-hint')).not.toBeNull();

      const row = root.querySelector('app-item-line .summary') as HTMLElement;
      row.getBoundingClientRect = () => ({ width: 300 }) as DOMRect;
      for (const [type, x] of [
        ['pointerdown', 300],
        ['pointermove', 290],
        ['pointermove', 150],
        ['pointerup', 150],
      ] as const) {
        row.dispatchEvent(new PointerEvent(type, { clientX: x, clientY: 100, bubbles: true }));
      }
      fixture.detectChanges();
      expect(root.querySelector('.swipe-hint')).toBeNull();

      TestBed.resetTestingModule();
      TestBed.configureTestingModule({
        imports: [Kitchen],
        providers: [
          provideHttpClient(),
          provideHttpClientTesting(),
          provideRouter([]),
          provideTranslateService(),
        ],
      });
      http = TestBed.inject(HttpTestingController);
      expect(load().root.querySelector('.swipe-hint')).toBeNull();
    });

    it('is not shown over an empty kitchen', () => {
      const fixture = TestBed.createComponent(Kitchen);
      fixture.detectChanges();
      http.expectOne(`${environment.apiUrl}/items`).flush(today([]));
      fixture.detectChanges();

      expect((fixture.nativeElement as HTMLElement).querySelector('.swipe-hint')).toBeNull();
    });
  });

  it('filters by place and by name together', () => {
    const fixture = TestBed.createComponent(Kitchen);
    fixture.detectChanges();
    const milk = pack(1, 'Milk');
    const peas = { ...pack(2, 'Peas'), storage: 'freezer' as const };
    const pasta = { ...pack(3, 'Pasta'), storage: 'pantry' as const };
    http.expectOne(`${environment.apiUrl}/items`).flush(today([milk, peas, pasta]));
    fixture.detectChanges();

    const root = fixture.nativeElement as HTMLElement;
    const filters = [...root.querySelectorAll('.jump button')] as HTMLButtonElement[];
    expect(filters).toHaveLength(4);
    expect(filters[0].getAttribute('aria-pressed')).toBe('true');
    expect(showing(root)).toEqual(['Milk', 'Peas', 'Pasta']);

    filters[1].click();
    fixture.detectChanges();
    expect(filters[1].getAttribute('aria-pressed')).toBe('true');
    expect(showing(root)).toEqual(['Milk']);

    filters[0].click();
    const search = root.querySelector('input[type="search"]') as HTMLInputElement;
    search.value = 'pa';
    search.dispatchEvent(new Event('input'));
    fixture.detectChanges();
    expect(showing(root)).toEqual(['Pasta']);

    filters[1].click();
    fixture.detectChanges();
    expect(showing(root)).toEqual([]);
    expect(root.textContent).toContain('kitchen.no_match');

    search.value = 'PE';
    search.dispatchEvent(new Event('input'));
    filters[2].click();
    fixture.detectChanges();
    expect(showing(root)).toEqual(['Peas']);
  });
});
