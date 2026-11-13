export interface Fridge {
  id: string;
  name: string;
  token: string;
  join_code: string;
  locale: string;
  created_at: string;
  stats?: { items: number; captures: number; memo_open: number };
}

export type Phase = 'fresh' | 'aging' | 'at_risk' | 'ghost';
export type Storage = 'fridge' | 'freezer' | 'pantry';
export type Outcome = 'used' | 'wasted' | 'partial' | 'froze' | 'opened' | 'snooze';

export interface Item {
  id: number;
  display_name: string;
  canonical_name: string;
  category: string;
  raw_text: string | null;
  quantity: number | null;
  unit: string | null;
  storage: Storage;
  acquired_on: string;
  window_start: string;
  window_end: string;
  days_left: number;
  confidence: number;
  state: string;
  opened_on: string | null;
  snoozed_until: string | null;
  high_risk: boolean;
  added_by_name: string | null;
}

/** An item with the risk model's read on it, as returned by the Today screen. */
export interface ScoredItem extends Item {
  presence: number;
  spoilage: number;
  risk: number;
  phase: Phase;
  headline: string;
  alertable: boolean;
  life_fraction: number;
}

export interface Today {
  use_first: ScoredItem[];
  fine_for_now: ScoredItem[];
  probably_gone: ScoredItem[];
  sweep_count: number;
  as_of: string;
}

export interface CapturedItem {
  id: number;
  display_name: string;
  category: string;
  raw_text: string | null;
  quantity: number | null;
  unit: string | null;
  storage: Storage;
  window_end: string;
  days_left: number;
  confidence: number;
  needs_review: boolean;
  added_by_name: string | null;
}

export interface CaptureReview {
  capture: {
    id: number;
    source: string;
    kind: 'receipt' | 'food' | 'unclear';
    merchant: string | null;
    purchased_on: string | null;
    status: string;
    parse_confidence: number | null;
    line_count: number;
    transcript: string | null;
    notes: string | null;
  };
  items: CapturedItem[];
  suppressed: string[];
}

export interface MemoItem {
  id: number;
  name: string;
  note: string | null;
  done: boolean;
  source: string;
  position: number;
  created_at: string;
  added_by_name: string | null;
}

export interface Suggestion {
  name: string;
  category: string;
  reason: string;
}

export interface MemoPage {
  items: MemoItem[];
  suggestions: Suggestion[];
}

export interface RecipeIngredient {
  item_id: number | null;
  name: string;
  amount: string | null;
  optional: boolean;
  use_first: boolean;
}

/** A short idea built only from food already in this kitchen. */
export interface Recipe {
  title: string;
  minutes: number | null;
  ingredients: RecipeIngredient[];
  steps: string[];
  use_first_count: number;
}

export interface RecipeSuggestions {
  recipes: Recipe[];
  cached: boolean;
  mode: 'live' | 'stub';
}

export interface CostReport {
  mode: 'live' | 'stub';
  models: Record<string, { name: string; input_usd_per_m: number; output_usd_per_m: number }>;
  transcribe_usd_per_minute: number;
  totals: {
    calls: number;
    failures: number;
    usd: number;
    input_tokens: number;
    output_tokens: number;
  };
  by_purpose: {
    purpose: string;
    calls: number;
    usd: number;
    avg_ms: number;
    usd_per_call: number;
  }[];
  this_fridge: { calls: number; failures: number; usd: number };
}
