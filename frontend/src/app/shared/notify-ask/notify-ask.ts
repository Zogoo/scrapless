import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { TranslatePipe } from '@ngx-translate/core';

import { PushService } from '../../core/services/push.service';

/**
 * The one permission question. Asked after food is in the kitchen, never at
 * onboarding: doc 2 §2.7 puts every permission after the value moment, and an
 * empty kitchen has nothing to notify about. The capture review asks it after
 * the first foods land; Today asks it of a kitchen that was stocked before
 * notifications existed, or that never scans again.
 *
 * Answered once per phone: either answer hides it everywhere. `enable()` asks
 * the browser straight away, still inside the tap, because Safari refuses a
 * permission prompt that does not come from one.
 */
@Component({
  selector: 'app-notify-ask',
  imports: [TranslatePipe],
  templateUrl: './notify-ask.html',
  styleUrl: './notify-ask.scss',
  changeDetection: ChangeDetectionStrategy.Eager,
})
export class NotifyAsk {
  protected readonly push = inject(PushService);

  protected answer(yes: boolean): void {
    if (yes) void this.push.enable();
    else this.push.markAsked();
  }
}
