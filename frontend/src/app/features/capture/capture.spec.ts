import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { Router, provideRouter } from '@angular/router';
import { provideTranslateService } from '@ngx-translate/core';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { environment } from '../../../environments/environment';
import { CaptureReview } from '../../core/models';
import { Capture } from './capture';

function reviewOf(...ids: number[]): CaptureReview {
  return {
    capture: { id: 1, source: 'receipt', kind: 'receipt', notes: null },
    items: ids.map((id) => ({ id, display_name: `Item ${id}`, days_left: 5, needs_review: false })),
    suppressed: [],
  } as unknown as CaptureReview;
}

/** The surface the test drives; these members are protected on the component. */
interface ReviewSheet {
  review: { set(value: CaptureReview): void; (): CaptureReview | null };
  reject(id: number): void;
}

describe('Capture review', () => {
  let http: HttpTestingController;
  let sheet: ReviewSheet;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [Capture],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        provideRouter([]),
        provideTranslateService(),
      ],
    });
    sheet = TestBed.createComponent(Capture).componentInstance as unknown as ReviewSheet;
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    http.verify();
    TestBed.resetTestingModule();
  });

  it('deletes a line the user removes and keeps the rest', () => {
    sheet.review.set(reviewOf(1, 2));

    sheet.reject(2);
    const req = http.expectOne(`${environment.apiUrl}/items/2`);
    expect(req.request.method).toBe('DELETE');
    req.flush(null);

    expect(sheet.review()?.items.map((item) => item.id)).toEqual([1]);
  });

  it('leaves the review once the last line is removed', () => {
    const navigate = vi.spyOn(TestBed.inject(Router), 'navigate').mockResolvedValue(true);
    sheet.review.set(reviewOf(1));

    sheet.reject(1);
    http.expectOne(`${environment.apiUrl}/items/1`).flush(null);

    expect(navigate).toHaveBeenCalledWith(['/today']);
  });

  it('keeps the line when the delete fails', () => {
    sheet.review.set(reviewOf(1, 2));

    sheet.reject(2);
    http
      .expectOne(`${environment.apiUrl}/items/2`)
      .flush(null, { status: 503, statusText: 'Service Unavailable' });

    expect(sheet.review()?.items.map((item) => item.id)).toEqual([1, 2]);
  });
});
