import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

import { environment } from '../../../environments/environment';
import { CaptureReview, CostReport } from '../models';

@Injectable({ providedIn: 'root' })
export class CaptureService {
  private readonly http = inject(HttpClient);
  private readonly url = `${environment.apiUrl}/captures`;

  /**
   * One endpoint for every input. The server decides from the photo whether it
   * is looking at a receipt or at food, so the user never has to say which —
   * picking the right button is exactly the friction we are removing.
   */
  photo(blob: Blob, hint: 'receipt' | 'shelf_photo'): Observable<CaptureReview> {
    const form = new FormData();
    form.append('image', blob, 'capture.jpg');
    form.append('source', hint);
    return this.http.post<CaptureReview>(this.url, form);
  }

  /** The free path: the browser already did the speech-to-text. */
  spoken(transcript: string): Observable<CaptureReview> {
    return this.http.post<CaptureReview>(this.url, { source: 'voice', transcript });
  }

  /** The Safari path: no SpeechRecognition, so the audio goes up instead. */
  spokenAudio(blob: Blob, seconds: number): Observable<CaptureReview> {
    const form = new FormData();
    form.append('audio', blob, 'note.webm');
    form.append('source', 'voice');
    form.append('duration_seconds', String(seconds));
    return this.http.post<CaptureReview>(this.url, form);
  }

  typed(text: string, source: 'text' | 'grid' = 'text'): Observable<CaptureReview> {
    return this.http.post<CaptureReview>(this.url, { source, text });
  }

  costs(): Observable<CostReport> {
    return this.http.get<CostReport>(`${environment.apiUrl}/costs`);
  }
}
