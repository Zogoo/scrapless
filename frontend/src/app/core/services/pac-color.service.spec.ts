import { TestBed } from '@angular/core/testing';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { PacColorService } from './pac-color.service';

describe('PacColorService', () => {
  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({});
  });

  afterEach(() => {
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('starts on classic yellow', () => {
    expect(TestBed.inject(PacColorService).color()).toBe('#ffcc00');
  });

  it('remembers a choice on this phone', () => {
    const service = TestBed.inject(PacColorService);

    service.use('sky');

    expect(service.color()).toBe('#4fc3f7');
    expect(localStorage.getItem('scrapless_pac')).toBe('sky');
    expect(TestBed.inject(PacColorService).color()).toBe('#4fc3f7');
  });

  it('ignores a colour this phone does not offer', () => {
    localStorage.setItem('scrapless_pac', 'nope');
    const service = TestBed.inject(PacColorService);

    service.use('nope');

    expect(service.color()).toBe('#ffcc00');
    expect(localStorage.getItem('scrapless_pac')).toBe('nope');
  });
});
