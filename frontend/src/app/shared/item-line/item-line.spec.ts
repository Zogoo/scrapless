import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { TranslateService, provideTranslateService } from '@ngx-translate/core';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { environment } from '../../../environments/environment';
import { ScoredItem, Storage } from '../../core/models';
import { ItemsService } from '../../core/services/items.service';
import { UndoService } from '../../core/services/undo.service';
import { ItemLine } from './item-line';
import { KitchenLine, lineFor, toLines } from './line';

function pack(
  id: number,
  amountLeft = 1,
  name = 'milk',
  windowEnd = '2026-11-20',
  openedOn: string | null = null,
  phase: ScoredItem['phase'] = 'fresh',
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
    phase,
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
  nudge(event: KeyboardEvent): void;
  releaseNudge(event: KeyboardEvent): void;
  move(item: ScoredItem, storage: Storage): void;
  resolve(item: ScoredItem, outcome: 'wasted'): void;
}

function slider(percent: number): Event {
  return { target: { value: String(percent) } } as unknown as Event;
}

/** What the first move of a drag sends. `start` is the percent before that move. */
function sliderOpen(start: number) {
  return { outcome: 'opened', source: 'slider', start_percent: start };
}

const RADISH = '/branding/rettich/mascot/rettich';

function thumb(root: ParentNode): string | null {
  return root.querySelector('.bite img')?.getAttribute('src') ?? null;
}

/** The card is closed until the one-liner is tapped. Slider specs need it open. */
function reveal(fixture: { detectChanges(): void; nativeElement: HTMLElement }): void {
  fixture.detectChanges();
  const toggle = fixture.nativeElement.querySelector('.toggle') as HTMLButtonElement | null;
  if (toggle?.getAttribute('aria-expanded') === 'false') {
    toggle.click();
    fixture.detectChanges();
  }
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

  it('starts as one line and opens and closes from that line', () => {
    const fixture = TestBed.createComponent(ItemLine);
    const translate = TestBed.inject(TranslateService);
    translate.setTranslation('en', { kitchen: { packs: '{{amount}} pk.' } });
    translate.use('en');
    const milk = pack(1);
    milk.display_name = 'Milk';
    milk.headline = 'about 4 days left';
    fixture.componentRef.setInput('line', toLines([milk, pack(2)])[0]);
    fixture.detectChanges();

    const root = fixture.nativeElement as HTMLElement;
    const toggle = root.querySelector('.toggle') as HTMLButtonElement;
    expect(toggle.getAttribute('aria-expanded')).toBe('false');
    expect(root.querySelector('.slider')).toBeNull();
    expect(root.querySelector('.bite')).toBeNull();
    expect(root.querySelector('.row-actions')).toBeNull();
    expect(root.textContent).toContain('Milk');
    expect(root.textContent).toContain('about 4 days left');
    expect(root.textContent).toContain('2 pk.');
    expect(root.textContent).not.toContain('%');

    toggle.click();
    fixture.detectChanges();
    expect(toggle.getAttribute('aria-expanded')).toBe('true');
    expect(root.querySelector('.slider')).not.toBeNull();
    expect(root.querySelector('.bite')).not.toBeNull();
    expect(root.querySelector('.row-actions')).not.toBeNull();
    expect(root.querySelector('.headline')?.textContent).toContain('about 4 days left');

    toggle.click();
    fixture.detectChanges();
    expect(toggle.getAttribute('aria-expanded')).toBe('false');
    expect(root.querySelector('.slider')).toBeNull();
    expect(root.querySelector('.row-actions')).toBeNull();
  });

  it('keeps the high-risk edge on the collapsed line', () => {
    const fixture = TestBed.createComponent(ItemLine);
    const milk = pack(1);
    milk.high_risk = true;
    fixture.componentRef.setInput('line', toLines([milk])[0]);
    fixture.detectChanges();

    const root = fixture.nativeElement as HTMLElement;
    expect(root.classList.contains('high-risk')).toBe(true);
    expect(root.querySelector('.slider')).toBeNull();
  });

  it('does not collapse from the slider, the radish, or an action', () => {
    const fixture = TestBed.createComponent(ItemLine);
    fixture.componentRef.setInput('line', toLines([pack(1)])[0]);
    reveal(fixture);
    const root = fixture.nativeElement as HTMLElement;
    const toggle = root.querySelector('.toggle') as HTMLButtonElement;

    root.querySelector('.level')?.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
    root.querySelector('.bite')?.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
    fixture.detectChanges();
    expect(toggle.getAttribute('aria-expanded')).toBe('true');
    expect(root.querySelector('.slider')).not.toBeNull();

    (root.querySelector('.quiet') as HTMLButtonElement).click();
    fixture.detectChanges();
    expect(toggle.getAttribute('aria-expanded')).toBe('true');
    expect(root.querySelector('.slider')).not.toBeNull();

    const wasted = http.expectOne(`${environment.apiUrl}/items/1/resolve`);
    expect(wasted.request.body).toEqual({ outcome: 'wasted' });
    wasted.flush({});
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
  });

  it('drags the slider from a pointer on the radish', () => {
    const fixture = TestBed.createComponent(ItemLine);
    fixture.componentRef.setInput('line', toLines([pack(1), pack(2)])[0]);
    reveal(fixture);
    const root = fixture.nativeElement as HTMLElement;
    const input = root.querySelector('.level') as HTMLInputElement;
    const bite = root.querySelector('.bite') as HTMLElement;
    input.getBoundingClientRect = () =>
      ({
        left: 0,
        width: 226,
        top: 0,
        height: 48,
        right: 226,
        bottom: 48,
        x: 0,
        y: 0,
        toJSON() {
          return {};
        },
      }) as DOMRect;

    // The usable track is the width minus the 26px thumb. 100px left is half.
    const point = (type: string, x: number) =>
      new PointerEvent(type, {
        clientX: x,
        button: 0,
        bubbles: true,
        cancelable: true,
        pointerId: 1,
      });
    bite.dispatchEvent(point('pointerdown', 200));
    bite.dispatchEvent(point('pointermove', 100));
    bite.dispatchEvent(point('pointerup', 100));

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

  it('takes one whole pack off a 4-pack line, and the label stays a pack amount', () => {
    const fixture = TestBed.createComponent(ItemLine);
    const translate = TestBed.inject(TranslateService);
    translate.setTranslation('en', { kitchen: { packs: '{{amount}} pk.' } });
    translate.use('en');
    fixture.componentRef.setInput('line', toLines([pack(1), pack(2), pack(3), pack(4)])[0]);
    reveal(fixture);
    const screen = fixture.componentInstance as unknown as ItemLineScreen;
    const root = fixture.nativeElement as HTMLElement;
    expect(root.querySelector('.amount')?.textContent).toContain('4 pk.');

    const target = root.querySelector('.level') as HTMLInputElement;
    const down = {
      key: 'ArrowLeft',
      preventDefault() {},
      target,
    } as unknown as KeyboardEvent;
    screen.nudge(down);
    reveal(fixture);
    expect(root.querySelector('.amount')?.textContent).toContain('3 pk.');
    expect(root.querySelector('.amount')?.textContent).not.toContain('%');

    screen.releaseNudge(down);

    const opened = http.expectOne(`${environment.apiUrl}/items/1/resolve`);
    expect(opened.request.body).toEqual(sliderOpen(100));
    opened.flush({});
    const revert = http.expectOne(`${environment.apiUrl}/items/1/revert_open`);
    expect(revert.request.body).toEqual({ percent: 75 });
    revert.flush({});
    const req = http.expectOne(`${environment.apiUrl}/items/level`);
    expect(req.request.body).toEqual({ ids: [1, 2, 3, 4], level: 3 });
    req.flush({ items: [] });
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
  });

  it('uses the whole line when the slider reaches 0%', () => {
    const packs = [pack(1), pack(2, 0.5)];
    const items = TestBed.inject(ItemsService);
    items.today.set({
      use_first: packs,
      fine_for_now: [],
      probably_gone: [],
      sweep_count: 0,
      as_of: '2026-11-18',
      has_captured: true,
    });
    const screen = mount(toLines(packs)[0]);

    screen.commitLevel(slider(0));

    // The card leaves with the toast on release, before any reply. A 0% preview
    // would otherwise stay on screen as an empty card.
    expect(items.today()?.use_first).toEqual([]);
    expect(TestBed.inject(UndoService).notice()?.itemIds).toEqual([1, 2]);
    expect(TestBed.inject(UndoService).notice()?.message).toBe('undo.used_up');

    const opened = http.expectOne(`${environment.apiUrl}/items/1/resolve`);
    expect(opened.request.body).toEqual(sliderOpen(75));
    opened.flush({});
    const revert = http.expectOne(`${environment.apiUrl}/items/1/revert_open`);
    expect(revert.request.body).toEqual({ percent: 0 });
    revert.flush({});
    const req = http.expectOne(`${environment.apiUrl}/items/level`);
    expect(req.request.body).toEqual({ ids: [1, 2], level: 0 });
    req.flush({ items: [] });
    expect(items.today()?.use_first).toEqual([]);

    http.expectOne(`${environment.apiUrl}/items`).flush({
      use_first: [{ ...packs[0], amount_left: 0 }],
      fine_for_now: [],
      probably_gone: [],
      sweep_count: 0,
      as_of: '2026-11-18',
      has_captured: true,
    });
    expect(items.today()?.use_first).toEqual([]);
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

  it('labels the bars in packs, including a quarter of one', () => {
    const fixture = TestBed.createComponent(ItemLine);
    const translate = TestBed.inject(TranslateService);
    translate.setTranslation('en', {
      kitchen: { packs: '{{amount}} pk.', lock_closed: 'Unopened', lock_open: 'Opened' },
    });
    translate.use('en');
    fixture.componentRef.setInput('line', toLines([pack(1), pack(2)])[0]);
    reveal(fixture);

    const root = fixture.nativeElement as HTMLElement;
    expect(root.querySelector('.amount')?.textContent).toContain('2 pk.');
    expect(root.querySelector('.level')?.getAttribute('aria-valuetext')).toBe('2 pk.');

    fixture.componentRef.setInput('line', toLines([pack(3, 0.25)])[0]);
    reveal(fixture);
    expect(root.querySelector('.amount')?.textContent).toContain('¼ pk.');
  });

  it('throws away the soonest pack on a grouped line', () => {
    const later = pack(1, 1, 'milk', '2026-11-20');
    const soon = pack(2, 0.5, 'milk', '2026-11-14');
    const line = toLines([later, soon])[0];
    const screen = mount(line);

    screen.resolve(line.first, 'wasted');

    const req = http.expectOne(`${environment.apiUrl}/items/2/resolve`);
    expect(req.request.body).toEqual({ outcome: 'wasted' });
    req.flush({});
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
    expect(TestBed.inject(UndoService).notice()?.itemIds).toEqual([2]);
  });

  it('draws one bar per pack, even when both are the same colour', () => {
    const fixture = TestBed.createComponent(ItemLine);
    const translate = TestBed.inject(TranslateService);
    translate.setTranslation('en', { kitchen: { lock_closed: 'Unopened', lock_open: 'Opened' } });
    translate.use('en');
    fixture.componentRef.setInput('line', toLines([pack(1), pack(2)])[0]);
    reveal(fixture);

    const root = fixture.nativeElement as HTMLElement;
    const bands = root.querySelectorAll('.band');
    expect(bands).toHaveLength(2);
    expect(bands[0].getAttribute('data-phase')).toBe('fresh');
    expect(bands[1].getAttribute('data-phase')).toBe('fresh');
    expect(root.querySelector('.bands')?.getAttribute('style')).toContain('width: 100%');
    expect((root.querySelector('.level') as HTMLElement).style.backgroundImage).toBe('');
  });

  it('fills a partial pack out to the thumb', () => {
    const fixture = TestBed.createComponent(ItemLine);
    fixture.componentRef.setInput('line', toLines([pack(1, 0.75)])[0]);
    reveal(fixture);

    const root = fixture.nativeElement as HTMLElement;
    expect(root.querySelector('.bands')?.getAttribute('style')).toContain('width: 75%');
    // 0.75 would leave the bar at 56% of the track. The share stays ¾, scaled up.
    expect((root.querySelector('.band') as HTMLElement).style.flexGrow).toBe('750');
  });

  it('draws a closed radish while the pack is unopened', () => {
    const fixture = TestBed.createComponent(ItemLine);
    fixture.componentRef.setInput('line', toLines([pack(1)])[0]);
    const translate = TestBed.inject(TranslateService);
    translate.setTranslation('en', { kitchen: { lock_closed: 'Unopened', lock_open: 'Opened' } });
    translate.use('en');
    reveal(fixture);

    const root = fixture.nativeElement as HTMLElement;
    const bite = root.querySelector('.bite');
    expect(root.querySelectorAll('.bite')).toHaveLength(1);
    expect(bite?.getAttribute('data-bites')).toBe('0');
    expect(bite?.getAttribute('aria-label')).toBe('Unopened');
    expect(bite?.classList.contains('bitten')).toBe(false);
    expect(thumb(root)).toBe(`${RADISH}-fresh-light.svg`);
    const dark = bite?.querySelector('source');
    expect(dark?.getAttribute('srcset')).toBe(`${RADISH}-fresh.svg`);
    expect(dark?.getAttribute('media')).toBe('(prefers-color-scheme: dark)');
    expect(bite?.classList.contains('full')).toBe(true);
    expect(bite?.classList.contains('open')).toBe(false);
    expect(root.querySelector('.slider')?.getAttribute('style')).toContain('--p: 100');
  });

  it('takes the radish from the bar against the thumb', () => {
    const fixture = TestBed.createComponent(ItemLine);
    fixture.componentRef.setInput(
      'line',
      toLines([
        pack(1, 1, 'milk', '2026-11-14', null, 'at_risk'),
        pack(2, 1, 'milk', '2026-11-20', null, 'fresh'),
      ])[0],
    );
    reveal(fixture);

    expect(thumb(fixture.nativeElement)).toBe(`${RADISH}-today-light.svg`);
  });

  it('uses the bitten radish once opened, and none at 0%', () => {
    const fixture = TestBed.createComponent(ItemLine);
    const translate = TestBed.inject(TranslateService);
    translate.setTranslation('en', { kitchen: { lock_closed: 'Unopened', lock_open: 'Opened' } });
    translate.use('en');

    const show = (
      amount: number,
      openedOn: string | null = '2026-11-12',
      phase: ScoredItem['phase'] = 'fresh',
    ) => {
      fixture.componentRef.setInput(
        'line',
        lineFor(pack(1, amount, 'milk', '2026-11-20', openedOn, phase)),
      );
      reveal(fixture);
      return fixture.nativeElement as HTMLElement;
    };

    const full = show(1);
    expect(full.querySelector('.bite')?.getAttribute('data-bites')).toBe('0');
    expect(thumb(full)).toBe(`${RADISH}-fresh-opened-light.svg`);
    expect(full.querySelector('.bite')?.classList.contains('bitten')).toBe(true);
    expect(full.querySelector('.bite')?.classList.contains('full')).toBe(true);
    expect(full.querySelector('.bite')?.classList.contains('open')).toBe(false);

    for (const amount of [0.75, 0.5, 0.25]) {
      const open = show(amount);
      expect(open.querySelector('.bite')?.getAttribute('data-bites')).toBe('1');
      expect(open.querySelector('.bite')?.getAttribute('aria-label')).toBe('Opened');
      expect(thumb(open)).toBe(`${RADISH}-fresh-opened-light.svg`);
      expect(open.querySelector('.bite')?.classList.contains('full')).toBe(false);
      expect(open.querySelector('.bite')?.classList.contains('open')).toBe(true);
    }

    expect(thumb(show(0.5, '2026-11-12', 'aging'))).toBe(`${RADISH}-soon-opened-light.svg`);
    expect(thumb(show(0.5, '2026-11-12', 'at_risk'))).toBe(`${RADISH}-today-opened-light.svg`);
    expect(thumb(show(0.5, '2026-11-12', 'ghost'))).toBe(`${RADISH}-today-opened-light.svg`);

    const gone = show(0);
    expect(gone.querySelector('.bite')?.getAttribute('data-bites')).toBe('4');
    expect(gone.querySelector('.bite')?.getAttribute('aria-label')).toBe('Opened');
    expect(thumb(gone)).toBeNull();

    const shut = show(0.5, null);
    expect(shut.querySelector('.bite')?.getAttribute('data-bites')).toBe('0');
    expect(shut.querySelector('.bite')?.classList.contains('bitten')).toBe(false);
    expect(thumb(shut)).toBe(`${RADISH}-fresh-light.svg`);
  });

  it('bites the radish on the first move', () => {
    const fixture = TestBed.createComponent(ItemLine);
    fixture.componentRef.setInput('line', toLines([pack(1)])[0]);
    const translate = TestBed.inject(TranslateService);
    translate.setTranslation('en', { kitchen: { lock_closed: 'Unopened', lock_open: 'Opened' } });
    translate.use('en');
    reveal(fixture);
    const screen = fixture.componentInstance as unknown as ItemLineScreen;

    screen.slide(slider(75));
    reveal(fixture);

    const root = fixture.nativeElement as HTMLElement;
    expect(root.querySelector('.bite')?.getAttribute('data-bites')).toBe('1');
    expect(root.querySelector('.bite')?.getAttribute('aria-label')).toBe('Opened');
    expect(thumb(root)).toBe(`${RADISH}-fresh-opened-light.svg`);
    expect(root.querySelector('.slider')?.getAttribute('style')).toContain('--p: 75');
    http.expectOne(`${environment.apiUrl}/items/1/resolve`).flush({});
  });

  it('closes the radish when the thumb slides back to unopened', () => {
    const fixture = TestBed.createComponent(ItemLine);
    fixture.componentRef.setInput('line', toLines([pack(1)])[0]);
    reveal(fixture);
    const screen = fixture.componentInstance as unknown as ItemLineScreen;

    screen.slide(slider(50));
    reveal(fixture);
    expect(thumb(fixture.nativeElement)).toBe(`${RADISH}-fresh-opened-light.svg`);

    screen.slide(slider(100));
    reveal(fixture);

    const bite = fixture.nativeElement.querySelector('.bite');
    expect(bite?.getAttribute('data-bites')).toBe('0');
    expect(thumb(fixture.nativeElement)).toBe(`${RADISH}-fresh-light.svg`);
    http.expectOne(`${environment.apiUrl}/items/1/resolve`).flush({});
  });

  it('warns when this drag opened the pack and then came back', () => {
    const fixture = TestBed.createComponent(ItemLine);
    fixture.componentRef.setInput('line', toLines([pack(1)])[0]);
    const translate = TestBed.inject(TranslateService);
    translate.setTranslation('en', {
      kitchen: { accidental_open: 'Accidental touch. This is unopened again.' },
    });
    translate.use('en');
    const screen = fixture.componentInstance as unknown as ItemLineScreen;

    screen.slide(slider(50));
    screen.commitLevel(slider(100));

    http.expectOne(`${environment.apiUrl}/items/1/resolve`).flush({});
    http.expectOne(`${environment.apiUrl}/items/1/revert_open`).flush({ opened_on: null });
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
    reveal(fixture);

    const root = fixture.nativeElement as HTMLElement;
    expect(root.querySelector('.accidental')?.textContent).toContain(
      'Accidental touch. This is unopened again.',
    );
    expect(root.querySelector('.bite')?.getAttribute('data-bites')).toBe('0');
    expect(thumb(root)).toBe(`${RADISH}-fresh-light.svg`);
  });

  // A new pack, opened on the previous release, then put back to full. This
  // drag did not send the open, and it does not start at the percent the open
  // was made from. The note still shows, because the pack is unopened again.
  it('warns when a later release undoes an open this slider saved', () => {
    const fixture = TestBed.createComponent(ItemLine);
    fixture.componentRef.setInput(
      'line',
      toLines([pack(1, 0.5, 'potato', '2026-11-20', '2026-11-17')])[0],
    );
    const translate = TestBed.inject(TranslateService);
    translate.setTranslation('en', {
      kitchen: { accidental_open: 'Accidental touch. This is unopened again.' },
    });
    translate.use('en');
    const screen = fixture.componentInstance as unknown as ItemLineScreen;

    screen.slide(slider(100));
    screen.commitLevel(slider(100));

    http.expectNone(`${environment.apiUrl}/items/1/resolve`);
    http.expectOne(`${environment.apiUrl}/items/1/revert_open`).flush({ opened_on: null });
    http.expectOne(`${environment.apiUrl}/items/level`).flush({ items: [] });
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
    reveal(fixture);

    const root = fixture.nativeElement as HTMLElement;
    expect(root.querySelector('.accidental')?.textContent).toContain(
      'Accidental touch. This is unopened again.',
    );
    expect(thumb(root)).toBe(`${RADISH}-fresh-light.svg`);
  });

  // The open was latched while the line still had no date. The list then
  // caught up, and a later release restored the unopened window. The thumb
  // follows that pack: closed, and the freshness the list sent back.
  it('closes the radish when the restored pack is unopened', () => {
    const fixture = TestBed.createComponent(ItemLine);
    const opened = pack(1, 0.5, 'potato', '2026-11-20', '2026-11-17', 'aging');
    fixture.componentRef.setInput('line', toLines([pack(1)])[0]);
    reveal(fixture);
    const screen = fixture.componentInstance as unknown as ItemLineScreen;

    screen.slide(slider(50));
    http.expectOne(`${environment.apiUrl}/items/1/resolve`).flush({ opened_on: '2026-11-17' });
    screen.commitLevel(slider(50));
    http.expectOne(`${environment.apiUrl}/items/1/revert_open`).flush({ opened_on: '2026-11-17' });
    http.expectOne(`${environment.apiUrl}/items/level`).flush({ items: [] });
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });

    fixture.componentRef.setInput('line', toLines([opened])[0]);
    reveal(fixture);
    expect(thumb(fixture.nativeElement)).toBe(`${RADISH}-soon-opened-light.svg`);

    const restored = pack(1, 1, 'potato', '2026-11-25', null, 'fresh');
    screen.slide(slider(100));
    screen.commitLevel(slider(100));
    // The reply can still carry the old date. The list is what was restored.
    http.expectOne(`${environment.apiUrl}/items/1/revert_open`).flush({ opened_on: '2026-11-17' });
    http.expectOne(`${environment.apiUrl}/items/level`).flush({ items: [] });
    http.expectOne(`${environment.apiUrl}/items`).flush({
      use_first: [restored],
      fine_for_now: [],
      probably_gone: [],
    });
    fixture.componentRef.setInput('line', toLines([restored])[0]);
    reveal(fixture);

    expect(thumb(fixture.nativeElement)).toBe(`${RADISH}-fresh-light.svg`);
  });

  it('does not warn when a pack that was already open comes back to the start', () => {
    const fixture = TestBed.createComponent(ItemLine);
    fixture.componentRef.setInput(
      'line',
      toLines([pack(1, 1, 'milk', '2026-11-20', '2026-11-12')])[0],
    );
    const screen = fixture.componentInstance as unknown as ItemLineScreen;

    screen.slide(slider(50));
    screen.commitLevel(slider(100));

    http.expectNone(`${environment.apiUrl}/items/1/resolve`);
    // The server leaves opened_on set: this open was not the slider's to undo.
    http.expectOne(`${environment.apiUrl}/items/1/revert_open`).flush({ opened_on: '2026-11-12' });
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });
    reveal(fixture);

    const root = fixture.nativeElement as HTMLElement;
    expect(root.querySelector('.accidental')).toBeNull();
    expect(thumb(root)).toBe(`${RADISH}-fresh-opened-light.svg`);
    expect(root.querySelector('.bite')?.classList.contains('full')).toBe(true);
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

    expect(TestBed.inject(UndoService).notice()?.itemIds).toEqual([4]);
  });

  // "Where is the Sojaghurt now?" moved one of its two packs and split the line.
  it('moves every pack on the line, and one Undo puts them all back', () => {
    const line = toLines([pack(4, 1, 'Joghurt'), pack(5, 1, 'Joghurt')])[0];
    const screen = mount(line);

    screen.move(line.first, 'fridge');

    for (const id of [4, 5]) {
      const req = http.expectOne(`${environment.apiUrl}/items/${id}/resolve`);
      expect(req.request.body).toEqual({ outcome: 'moved', to: 'fridge' });
      req.flush({});
    }
    http.expectOne(`${environment.apiUrl}/items`).flush({ use_first: [], fine_for_now: [] });

    expect(TestBed.inject(UndoService).notice()?.itemIds).toEqual([4, 5]);
  });
});
