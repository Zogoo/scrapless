import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { provideTranslateService } from '@ngx-translate/core';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { environment } from '../../../environments/environment';
import { ScoredItem, Storage } from '../../core/models';
import { UndoService } from '../../core/services/undo.service';
import { Kitchen } from './kitchen';
import { KitchenLine, toLines } from './kitchen-line';

function pack(
  id: number,
  amountLeft = 1,
  name = 'milk',
  windowEnd = '2026-11-20',
  openedOn: string | null = null,
): ScoredItem {
  return {
    id,
    display_name: name,
    canonical_name: name,
    storage: 'fridge',
    amount_left: amountLeft,
    window_start: '2026-11-14',
    window_end: windowEnd,
    opened_on: openedOn,
    phase: 'fresh',
  } as ScoredItem;
}

// jsdom has <dialog> but not its methods; every browser the app supports does.
HTMLDialogElement.prototype.showModal ??= function (this: HTMLDialogElement) {
  this.open = true;
};
HTMLDialogElement.prototype.close ??= function (this: HTMLDialogElement) {
  this.open = false;
};

/** The surface the test drives; these members are protected on the component. */
interface KitchenScreen {
  beginGesture(line: KitchenLine): void;
  slide(line: KitchenLine, event: Event): void;
  commitLevel(line: KitchenLine, event: Event): void;
  move(item: ScoredItem, storage: Storage): void;
}

function slider(percent: number): Event {
  return { target: { value: String(percent) } } as unknown as Event;
}

describe('Kitchen slider', () => {
  let http: HttpTestingController;
  let screen: KitchenScreen;

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
    screen = TestBed.createComponent(Kitchen).componentInstance as unknown as KitchenScreen;
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    TestBed.resetTestingModule();
  });

  it('stops only on quarters of the line', () => {
    const [line] = toLines([pack(1), pack(2)]);

    screen.commitLevel(line, slider(50));

    const opened = http.expectOne(`${environment.apiUrl}/items/1/resolve`);
    expect(opened.request.body).toEqual({ outcome: 'opened' });
    opened.flush({});
    const req = http.expectOne(`${environment.apiUrl}/items/level`);
    expect(req.request.body).toEqual({ ids: [1, 2], level: 1 });
    req.flush({ items: [] });
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
  });

  it('uses the whole line when the slider reaches 0%', () => {
    const [line] = toLines([pack(1), pack(2, 0.5)]);

    screen.commitLevel(line, slider(0));

    http.expectOne(`${environment.apiUrl}/items/1/resolve`).flush({});
    const req = http.expectOne(`${environment.apiUrl}/items/level`);
    expect(req.request.body).toEqual({ ids: [1, 2], level: 0 });
    req.flush({ items: [] });
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
  });

  it('opens the soonest pack on the first move, and not again', () => {
    const [line] = toLines([pack(1, 1, 'milk', '2026-11-20'), pack(2, 1, 'milk', '2026-11-14')]);

    screen.slide(line, slider(75));
    const req = http.expectOne(`${environment.apiUrl}/items/2/resolve`);
    expect(req.request.body).toEqual({ outcome: 'opened' });
    req.flush({});

    screen.slide(line, slider(50));
    http.expectNone(`${environment.apiUrl}/items/2/resolve`);
  });

  it('puts the dates back and clears opened when the slider returns to where it started', () => {
    const [line] = toLines([pack(1), pack(2)]);

    screen.beginGesture(line);
    screen.slide(line, slider(50));
    screen.commitLevel(line, slider(100));

    const opened = http.expectOne(`${environment.apiUrl}/items/1/resolve`);
    expect(opened.request.body).toEqual({ outcome: 'opened' });
    opened.flush({});
    const undo = http.expectOne(`${environment.apiUrl}/items/1/undo`);
    undo.flush({});
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
    http.expectNone(`${environment.apiUrl}/items/level`);
  });

  it('keeps the pack opened when the slider stays at a new percentage', () => {
    const [line] = toLines([pack(1), pack(2)]);

    screen.slide(line, slider(50));
    http.expectOne(`${environment.apiUrl}/items/1/resolve`).flush({});
    screen.commitLevel(line, slider(50));

    const req = http.expectOne(`${environment.apiUrl}/items/level`);
    expect(req.request.body).toEqual({ ids: [1, 2], level: 1 });
    req.flush({ items: [] });
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
    http.expectNone(`${environment.apiUrl}/items/1/undo`);
  });

  it('changes only the amount of a pack that was already opened', () => {
    const [line] = toLines([pack(1, 1, 'milk', '2026-11-20', '2026-11-12'), pack(2)]);

    screen.slide(line, slider(50));
    screen.commitLevel(line, slider(50));

    http.expectNone(`${environment.apiUrl}/items/1/resolve`);
    const req = http.expectOne(`${environment.apiUrl}/items/level`);
    expect(req.request.body).toEqual({ ids: [1, 2], level: 1 });
    req.flush({ items: [] });
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
    http.expectNone(`${environment.apiUrl}/items/1/undo`);
  });

  // Bread to the cupboard is one request; the server decides what that does
  // to its window (a thaw, a freeze, or the same clock in a new place).
  it('moves food with one request and says where it went', () => {
    const bread = pack(4, 1, 'Brot');

    screen.move(bread, 'pantry');

    const req = http.expectOne(`${environment.apiUrl}/items/4/resolve`);
    expect(req.request.body).toEqual({ outcome: 'moved', to: 'pantry' });
    req.flush({});
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });

    expect(TestBed.inject(UndoService).notice()?.itemId).toBe(4);
  });
});
