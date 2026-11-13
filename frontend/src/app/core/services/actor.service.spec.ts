import { TestBed } from '@angular/core/testing';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { ActorService, cleanActorName } from './actor.service';

describe('cleanActorName', () => {
  it('trims, collapses space and stops at forty characters', () => {
    expect(cleanActorName('  Mama  ')).toBe('Mama');
    expect(cleanActorName('M'.repeat(80))).toHaveLength(40);
  });
});

describe('ActorService', () => {
  beforeEach(() => {
    localStorage.clear();
    TestBed.configureTestingModule({});
  });

  afterEach(() => {
    localStorage.clear();
    TestBed.resetTestingModule();
  });

  it('keeps the name on this phone', () => {
    const service = TestBed.inject(ActorService);

    service.setName('  Mama ');

    expect(service.name()).toBe('Mama');
    expect(localStorage.getItem('scrapless_actor')).toBe('Mama');
  });

  it('forgets a blank name', () => {
    localStorage.setItem('scrapless_actor', 'Mama');
    const service = TestBed.inject(ActorService);

    service.setName('   ');

    expect(service.name()).toBe('');
    expect(localStorage.getItem('scrapless_actor')).toBeNull();
  });
});
