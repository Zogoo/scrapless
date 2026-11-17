import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { provideTranslateService } from '@ngx-translate/core';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { environment } from '../../../environments/environment';
import { ScoredItem, Storage } from '../../core/models';
import { UndoService } from '../../core/services/undo.service';
import { ItemLine } from './item-line';
import { KitchenLine, toLines } from './line';

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
interface ItemLineScreen {
  beginGesture(): void;
  slide(event: Event): void;
  commitLevel(event: Event): void;
  move(item: ScoredItem, storage: Storage): void;
}

function slider(percent: number): Event {
  return { target: { value: String(percent) } } as unknown as Event;
}

/** What the first move of a drag sends. `start` is the percent before that move. */
function sliderOpen(start: number) {
  return { outcome: 'opened', source: 'slider', start_percent: start };
}

describe('Item line', () => {
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [ItemLine],
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

  function mount(line: KitchenLine): ItemLineScreen {
    const fixture = TestBed.createComponent(ItemLine);
    fixture.componentRef.setInput('line', line);
    return fixture.componentInstance as unknown as ItemLineScreen;
  }

  it('stops only on quarters of the line', () => {
    const screen = mount(toLines([pack(1), pack(2)])[0]);

    screen.commitLevel(slider(50));

    const opened = http.expectOne(`${environment.apiUrl}/items/1/resolve`);
    expect(opened.request.body).toEqual(sliderOpen(100));
    opened.flush({});
    const revert = http.expectOne(`${environment.apiUrl}/items/1/revert_open`);
    expect(revert.request.body).toEqual({ percent: 50 });
    revert.flush({});
    const req = http.expectOne(`${environment.apiUrl}/items/level`);
    expect(req.request.body).toEqual({ ids: [1, 2], level: 1 });
    req.flush({ items: [] });
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
  });

  it('uses the whole line when the slider reaches 0%', () => {
    const screen = mount(toLines([pack(1), pack(2, 0.5)])[0]);

    screen.commitLevel(slider(0));

    const opened = http.expectOne(`${environment.apiUrl}/items/1/resolve`);
    expect(opened.request.body).toEqual(sliderOpen(75));
    opened.flush({});
    const revert = http.expectOne(`${environment.apiUrl}/items/1/revert_open`);
    expect(revert.request.body).toEqual({ percent: 0 });
    revert.flush({});
    const req = http.expectOne(`${environment.apiUrl}/items/level`);
    expect(req.request.body).toEqual({ ids: [1, 2], level: 0 });
    req.flush({ items: [] });
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
  });

  it('opens the soonest pack on the first move, and not again', () => {
    const screen = mount(
      toLines([pack(1, 1, 'milk', '2026-11-20'), pack(2, 1, 'milk', '2026-11-14')])[0],
    );

    screen.slide(slider(75));
    const req = http.expectOne(`${environment.apiUrl}/items/2/resolve`);
    expect(req.request.body).toEqual(sliderOpen(100));
    req.flush({});

    screen.slide(slider(50));
    http.expectNone(`${environment.apiUrl}/items/2/resolve`);
  });

  it('puts the dates back and clears opened when the slider returns to where it started', () => {
    const screen = mount(toLines([pack(1), pack(2)])[0]);

    screen.beginGesture();
    screen.slide(slider(50));
    screen.commitLevel(slider(100));

    const opened = http.expectOne(`${environment.apiUrl}/items/1/resolve`);
    expect(opened.request.body).toEqual(sliderOpen(100));
    opened.flush({});
    const revert = http.expectOne(`${environment.apiUrl}/items/1/revert_open`);
    expect(revert.request.body).toEqual({ percent: 100 });
    revert.flush({});
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
    http.expectNone(`${environment.apiUrl}/items/level`);
  });

  it('keeps the pack opened when the slider stays at a new percentage', () => {
    const screen = mount(toLines([pack(1), pack(2)])[0]);

    screen.slide(slider(50));
    http.expectOne(`${environment.apiUrl}/items/1/resolve`).flush({});
    screen.commitLevel(slider(50));

    const revert = http.expectOne(`${environment.apiUrl}/items/1/revert_open`);
    expect(revert.request.body).toEqual({ percent: 50 });
    revert.flush({});
    const req = http.expectOne(`${environment.apiUrl}/items/level`);
    expect(req.request.body).toEqual({ ids: [1, 2], level: 1 });
    req.flush({ items: [] });
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
    http.expectNone(`${environment.apiUrl}/items/1/undo`);
  });

  it('changes only the amount of a pack that was already opened', () => {
    const screen = mount(toLines([pack(1, 1, 'milk', '2026-11-20', '2026-11-12'), pack(2)])[0]);

    screen.slide(slider(50));
    screen.commitLevel(slider(50));

    http.expectNone(`${environment.apiUrl}/items/1/resolve`);
    const revert = http.expectOne(`${environment.apiUrl}/items/1/revert_open`);
    expect(revert.request.body).toEqual({ percent: 50 });
    revert.flush({});
    const req = http.expectOne(`${environment.apiUrl}/items/level`);
    expect(req.request.body).toEqual({ ids: [1, 2], level: 1 });
    req.flush({ items: [] });
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
    http.expectNone(`${environment.apiUrl}/items/1/undo`);
  });

  // The open was saved on an earlier drag, so this one starts at half. Letting
  // go back at 100% — where that earlier drag began — asks to undo the open.
  it('undoes a saved open when a later release is back at the starting percent', () => {
    const potato = pack(1, 0.5, 'potato', '2026-11-20', '2026-11-17');
    const screen = mount(toLines([potato])[0]);

    screen.slide(slider(100));
    screen.commitLevel(slider(100));

    http.expectNone(`${environment.apiUrl}/items/1/resolve`);
    const revert = http.expectOne(`${environment.apiUrl}/items/1/revert_open`);
    expect(revert.request.body).toEqual({ percent: 100 });
    revert.flush({});
    const req = http.expectOne(`${environment.apiUrl}/items/level`);
    expect(req.request.body).toEqual({ ids: [1], level: 1 });
    req.flush({ items: [] });
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
  });

  // Bread to the cupboard is one request; the server decides what that does
  // to its window (a thaw, a freeze, or the same clock in a new place).
  it('moves food with one request and says where it went', () => {
    const bread = pack(4, 1, 'Brot');
    const screen = mount(toLines([bread])[0]);

    screen.move(bread, 'pantry');

    const req = http.expectOne(`${environment.apiUrl}/items/4/resolve`);
    expect(req.request.body).toEqual({ outcome: 'moved', to: 'pantry' });
    req.flush({});
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });

    expect(TestBed.inject(UndoService).notice()?.itemId).toBe(4);
  });
});
