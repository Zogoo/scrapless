import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideTranslateService } from '@ngx-translate/core';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { environment } from '../../../environments/environment';
import { ScoredItem } from '../models';
import { UndoService } from './undo.service';

describe('UndoService', () => {
  let service: UndoService;
  let http: HttpTestingController;
  const broccoli = { id: 7, display_name: 'Broccoli' } as ScoredItem;

  beforeEach(() => {
    vi.useFakeTimers();
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting(), provideTranslateService()],
    });
    service = TestBed.inject(UndoService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    vi.useRealTimers();
    TestBed.resetTestingModule();
  });

  it('offers to take back the tap, then goes away by itself', () => {
    service.showOutcome(broccoli, 'wasted');
    expect(service.notice()?.itemId).toBe(7);

    vi.advanceTimersByTime(UndoService.SHOW_MS);
    expect(service.notice()).toBeNull();
  });

  it('undoes on the server and then reloads the kitchen', () => {
    service.showOutcome(broccoli, 'used');

    service.undo();
    http.expectOne(`${environment.apiUrl}/items/7/undo`).flush({});
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });

    expect(service.notice()).toBeNull();
  });

  it('says why when the server refuses', () => {
    service.showOutcome(broccoli, 'used');

    service.undo();
    http
      .expectOne(`${environment.apiUrl}/items/7/undo`)
      .flush({ error: "That one can't be undone any more." }, { status: 422, statusText: 'x' });

    expect(service.notice()?.itemId).toBeUndefined();
  });
});
