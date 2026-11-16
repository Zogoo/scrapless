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

function pack(id: number, amountLeft = 1, name = 'milk'): ScoredItem {
  return {
    id,
    display_name: name,
    canonical_name: name,
    storage: 'fridge',
    amount_left: amountLeft,
    window_end: '2026-11-20',
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
  step(line: KitchenLine, delta: number): void;
  move(item: ScoredItem, storage: Storage): void;
}

describe('Kitchen steps', () => {
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

  // The slider is a drag; doc 3 R3-AC3 asks for a way that is not.
  it('lowers a line by a quarter without a drag', () => {
    const [line] = toLines([pack(1), pack(2)]);

    screen.step(line, -0.25);

    const req = http.expectOne(`${environment.apiUrl}/items/level`);
    expect(req.request.body).toEqual({ ids: [1, 2], level: 1.75 });
  });

  it('never steps past empty or full', () => {
    const [line] = toLines([pack(1, 0.1)]);

    screen.step(line, -0.25);
    expect(http.expectOne(`${environment.apiUrl}/items/level`).request.body.level).toBe(0);

    const [full] = toLines([pack(3, 1, 'bread')]);
    screen.step(full, 0.25);
    expect(http.expectOne(`${environment.apiUrl}/items/level`).request.body.level).toBe(1);
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
