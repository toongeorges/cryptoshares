import { NgModule } from '@angular/core';
import { RouterModule, Routes } from '@angular/router';
import { ExchangeComponent } from './page/exchange/exchange.component';
import { SeedtokensComponent } from './page/seedtokens/seedtokens.component';
import { SharesComponent } from './page/shares/shares.component';

const routes: Routes = [
  { path: 'exchange', component: ExchangeComponent },
  { path: 'shares', component: SharesComponent },
  { path: 'seedtokens', component: SeedtokensComponent },
  { path: '', redirectTo: '/exchange', pathMatch: 'full' }
];

@NgModule({
  imports: [RouterModule.forRoot(routes)],
  exports: [RouterModule]
})
export class AppRoutingModule {}
