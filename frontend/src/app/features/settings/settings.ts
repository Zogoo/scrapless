import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { DecimalPipe } from '@angular/common';
import { TranslatePipe } from '@ngx-translate/core';

import { FridgeService, kitchenShareUrl } from '../../core/services/fridge.service';
import { ActorService } from '../../core/services/actor.service';
import { CaptureService } from '../../core/services/capture.service';
import { InstallService } from '../../core/services/install.service';
import { qrImageSrc } from '../../core/qr-image';
import { CostReport } from '../../core/models';

@Component({
  selector: 'app-settings',
  imports: [FormsModule, DecimalPipe, TranslatePipe],
  templateUrl: './settings.html',
  styleUrl: './settings.scss',
})
export class Settings implements OnInit {
  protected readonly fridge = inject(FridgeService);
  protected readonly actor = inject(ActorService);
  protected readonly install = inject(InstallService);
  private readonly captures = inject(CaptureService);
  private readonly router = inject(Router);

  protected readonly name = signal('');
  protected readonly saved = signal(false);
  protected readonly actorName = signal('');
  protected readonly actorSaved = signal(false);
  protected readonly copied = signal(false);
  protected readonly costs = signal<CostReport | null>(null);
  protected readonly confirmingForget = signal(false);

  protected readonly shareLink = computed(() => {
    const code = this.fridge.fridge()?.join_code;
    return code ? kitchenShareUrl(location.origin, code) : '';
  });

  protected readonly qrSrc = computed(() => {
    const link = this.shareLink();
    return link ? qrImageSrc(link) : '';
  });

  ngOnInit(): void {
    this.name.set(this.fridge.fridge()?.name ?? '');
    this.actorName.set(this.actor.name());
    this.captures.costs().subscribe({ next: (report) => this.costs.set(report) });
  }

  protected rename(): void {
    const name = this.name().trim();
    if (!name) return;

    this.fridge.rename(name).subscribe({
      next: () => {
        this.saved.set(true);
        setTimeout(() => this.saved.set(false), 2000);
      },
    });
  }

  protected saveActor(): void {
    this.actor.setName(this.actorName());
    this.actorSaved.set(true);
    setTimeout(() => this.actorSaved.set(false), 2000);
  }

  protected selectLink(event: Event): void {
    (event.target as HTMLInputElement).select();
  }

  protected async copyLink(link: string): Promise<void> {
    try {
      await navigator.clipboard.writeText(link);
      this.copied.set(true);
      setTimeout(() => this.copied.set(false), 2000);
    } catch {
      this.copied.set(false);
    }
  }

  protected async installApp(): Promise<void> {
    await this.install.promptInstall();
  }

  /** Erasure is a plain delete: there is no immutable log to shred. */
  protected forget(): void {
    this.fridge.forget().subscribe({ next: () => void this.router.navigate(['/welcome']) });
  }

  /** Cost per capture, which is the number the whole model rests on. */
  protected costPerCapture(report: CostReport): number {
    const receipts = report.by_purpose.find((row) => row.purpose === 'receipt_extract');
    return receipts?.usd_per_call ?? 0;
  }
}
