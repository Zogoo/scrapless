import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { environment } from '../../../environments/environment';
import { ScoredItem, Today } from '../models';

import { ItemsService } from './items.service';

function pack(id: number, amountLeft = 1): ScoredItem {
  return { id, amount_left: amountLeft, display_name: 'Pasta' } as ScoredItem;
}

function today(useFirst: ScoredItem[]): Today {
  return {
    use_first: useFirst,
    fine_for_now: [],
    probably_gone: [],
    sweep_count: 0,
    as_of: '2026-11-18',
    has_captured: true,
  };
}

describe('ItemsService', () => {
  let service: ItemsService;
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [provideHttpClient(), provideHttpClientTesting()],
    });
    service = TestBed.inject(ItemsService);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    TestBed.resetTestingModule();
  });

  it('takes used packs off the list Home and the Kitchen share', () => {
    service.today.set(today([pack(1), pack(2, 0.5)]));

    service.removeFromList([1, 2]);

    expect(service.today()?.use_first).toEqual([]);
  });

  it('does not put an empty pack back when the kitchen is reloaded', () => {
    service.load().subscribe();
    http.expectOne(`${environment.apiUrl}/items`).flush(today([pack(1, 0), pack(2, 0.75)]));

    expect(service.today()?.use_first.map((item) => item.id)).toEqual([2]);
  });

  it('ignores a reload that started before the packs were used up', () => {
    service.today.set(today([pack(1), pack(2, 0.5)]));
    service.load().subscribe();
    const stale = http.expectOne(`${environment.apiUrl}/items`);

    service.removeFromList([1, 2]);
    stale.flush(today([pack(1), pack(2, 0.5)]));

    expect(service.today()?.use_first).toEqual([]);
  });
});
