import { Routes } from '@angular/router';

import { fridgeGuard, noFridgeGuard } from './core/guards/fridge.guard';

export const routes: Routes = [
  {
    path: 'welcome',
    canActivate: [noFridgeGuard],
    loadComponent: () => import('./features/onboarding/onboarding').then((m) => m.Onboarding),
  },
  {
    path: 'today',
    canActivate: [fridgeGuard],
    loadComponent: () => import('./features/today/today').then((m) => m.Today),
  },
  {
    path: 'add',
    canActivate: [fridgeGuard],
    loadComponent: () => import('./features/capture/capture').then((m) => m.Capture),
  },
  {
    path: 'memo',
    canActivate: [fridgeGuard],
    loadComponent: () => import('./features/memo/memo').then((m) => m.Memo),
  },
  {
    path: 'kitchen',
    canActivate: [fridgeGuard],
    loadComponent: () => import('./features/kitchen/kitchen').then((m) => m.Kitchen),
  },
  {
    path: 'settings',
    canActivate: [fridgeGuard],
    loadComponent: () => import('./features/settings/settings').then((m) => m.Settings),
  },
  { path: '', pathMatch: 'full', redirectTo: 'today' },
  { path: '**', redirectTo: 'today' },
];
