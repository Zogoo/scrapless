import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { DecimalPipe } from '@angular/common';
import { TranslatePipe } from '@ngx-translate/core';

import { FridgeService } from '../../core/services/fridge.service';
import { CaptureService } from '../../core/services/capture.service';
import { InstallService } from '../../core/services/install.service';
import { CostReport } from '../../core/models';

@Component({
  selector: 'app-settings',
  imports: [FormsModule, DecimalPipe, TranslatePipe],
  templateUrl: './settings.html',
  styleUrl: './settings.scss',
})
export class Settings implements OnInit {
  protected readonly fridge = inject(FridgeService);
  protected readonly install = inject(InstallService);
  private readonly captures = inject(CaptureService);
  private readonly router = inject(Router);

  protected readonly name = signal('');
  protected readonly saved = signal(false);
  protected readonly costs = signal<CostReport | null>(null);
  protected readonly confirmingForget = signal(false);

  ngOnInit(): void {
    this.name.set(this.fridge.fridge()?.name ?? '');
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
