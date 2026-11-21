import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { provideTranslateService } from '@ngx-translate/core';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { environment } from '../../../environments/environment';
import { Onboarding } from './onboarding';

// Doc 2 §2.7: no required typing, and skipping is as easy as answering.
describe('Onboarding', () => {
  let http: HttpTestingController;

  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({
      imports: [Onboarding],
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

  function render() {
    const fixture = TestBed.createComponent(Onboarding);
    fixture.detectChanges();
    const root = fixture.nativeElement as HTMLElement;
    const chips = () => [...root.querySelectorAll<HTMLButtonElement>('.brotbox .choices button')];
    const start = () => {
      (root.querySelector('.actions .primary') as HTMLButtonElement).click();
      return http.expectOne(`${environment.apiUrl}/fridge`);
    };
    return { fixture, chips, start };
  }

  it('offers Keine, 1, 2, 3 and 4+, with nothing chosen', () => {
    const { chips } = render();

    expect(chips()).toHaveLength(5);
    expect(chips().every((chip) => chip.getAttribute('aria-pressed') === 'false')).toBe(true);
  });

  it('creates the kitchen without a Brotbox count when no chip is chosen', () => {
    const req = render().start();

    expect(req.request.body).toEqual({ name: null });
    req.flush({ id: 'x', name: 'Quiet Kitchen', token: 't', join_code: 'j' });
  });

  it('sends the chosen count', () => {
    const { fixture, chips, start } = render();

    chips()[2].click();
    fixture.detectChanges();
    const req = start();

    expect(req.request.body).toEqual({ name: null, brotbox_count: 2 });
    req.flush({ id: 'x', name: 'Quiet Kitchen', token: 't', join_code: 'j' });
  });

  it('stores 4 for 4+', () => {
    const { fixture, chips, start } = render();

    chips()[4].click();
    fixture.detectChanges();
    const req = start();

    expect(req.request.body).toEqual({ name: null, brotbox_count: 4 });
    req.flush({ id: 'x', name: 'Quiet Kitchen', token: 't', join_code: 'j' });
  });

  it('says "skip" until something is given, a count alone included', () => {
    const { fixture, chips } = render();
    const label = () =>
      (fixture.nativeElement as HTMLElement)
        .querySelector('.actions .primary')!
        .textContent!.trim();

    expect(label()).toBe('onboarding.skip');
    chips()[1].click();
    fixture.detectChanges();
    expect(label()).toBe('onboarding.name_it');
  });

  it('unchooses a chip tapped twice', () => {
    const { fixture, chips, start } = render();

    chips()[2].click();
    fixture.detectChanges();
    chips()[2].click();
    fixture.detectChanges();

    expect(chips()[2].getAttribute('aria-pressed')).toBe('false');
    const req = start();
    expect(req.request.body).toEqual({ name: null });
    req.flush({ id: 'x', name: 'Quiet Kitchen', token: 't', join_code: 'j' });
  });
});
