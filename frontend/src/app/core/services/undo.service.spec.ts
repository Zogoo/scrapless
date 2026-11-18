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

  it('lets the offer to take back the tap go by itself', () => {
    service.showOutcome(broccoli, 'wasted');
    vi.advanceTimersByTime(UndoService.SHOW_MS - 1);
    expect(service.notice()?.itemIds).toEqual([7]);

    vi.advanceTimersByTime(1);
    expect(service.notice()).toBeNull();
  });

  // WCAG 2.2.1: an Undo that runs away from someone reaching for it is one
  // they can never use.
  it('waits while someone is on the toast, then gives them the whole time again', () => {
    service.showOutcome(broccoli, 'wasted');
    vi.advanceTimersByTime(UndoService.SHOW_MS - 1);

    service.hold();
    vi.advanceTimersByTime(UndoService.SHOW_MS * 10);
    expect(service.notice()?.itemIds).toEqual([7]);

    service.release();
    vi.advanceTimersByTime(UndoService.SHOW_MS - 1);
    expect(service.notice()?.itemIds).toEqual([7]);
    vi.advanceTimersByTime(1);
    expect(service.notice()).toBeNull();
  });

  it('closes when asked', () => {
    service.showOutcome(broccoli, 'wasted');

    service.dismiss();
    expect(service.notice()).toBeNull();
  });

  it('lets a message with nothing to undo go by itself', () => {
    service.show({ message: 'Offline' });

    vi.advanceTimersByTime(UndoService.SHOW_MS);
    expect(service.notice()).toBeNull();
  });

  it('starts the time again when a new notice replaces the last one', () => {
    service.showOutcome(broccoli, 'used');
    vi.advanceTimersByTime(UndoService.SHOW_MS - 1);

    service.showOutcome(broccoli, 'wasted');
    vi.advanceTimersByTime(UndoService.SHOW_MS - 1);
    expect(service.notice()).not.toBeNull();
  });

  it('puts back every pack the slider used up, then reloads the kitchen', () => {
    service.showUsedUp([1, 2], 'Milch');
    expect(service.notice()?.itemIds).toEqual([1, 2]);
    expect(service.notice()?.message).toBe('undo.used_up');

    service.undo();
    http.expectOne(`${environment.apiUrl}/items/1/undo`).flush({});
    http.expectOne(`${environment.apiUrl}/items/2/undo`).flush({});
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });

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

    expect(service.notice()?.itemIds).toBeUndefined();
  });
});
