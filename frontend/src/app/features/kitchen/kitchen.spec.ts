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
  return [...root.querySelectorAll('li:not(.leaving) .name-btn')].map(
    (button) => button.textContent?.trim() ?? '',
  );
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

    const root = fixture.nativeElement as HTMLElement;
    expect(root.querySelector('.bite img')?.getAttribute('src')).toBe(
      '/branding/rettich/mascot/rettich-soon-opened.svg',
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
      '/branding/rettich/mascot/rettich-fresh.svg',
    );
  });
});
