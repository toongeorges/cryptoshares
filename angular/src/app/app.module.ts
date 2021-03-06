import { NgModule } from '@angular/core';
import { BrowserModule } from '@angular/platform-browser';

import { AppRoutingModule } from './app-routing.module';
import { AppComponent } from './app.component';
import { BrowserAnimationsModule } from '@angular/platform-browser/animations';

import { MaterialDesignModule } from './material-design.module';

import { MatIconRegistry } from '@angular/material/icon';
import { DomSanitizer } from '@angular/platform-browser';
import { SeedtokensComponent } from './page/seedtokens/seedtokens.component';
import { SharesComponent } from './page/shares/shares.component';
import { ExchangeComponent } from './page/exchange/exchange.component';
import { NewTokenComponent } from './page/seedtokens/new-token/new-token.component';
import { FormsModule } from '@angular/forms';
import { ProgressSpinnerOverlayComponent } from './page/progress-spinner-overlay/progress-spinner-overlay.component';
import { MintComponent } from './page/seedtokens/mint/mint.component';
import { ChangeOwnerComponent } from './page/seedtokens/change-owner/change-owner.component';
import { HttpClientModule } from '@angular/common/http';
import { NewShareComponent } from './page/shares/dialogs/new-share/new-share.component';
import { ChangeDecisionParametersComponent } from './page/shares/dialogs/change-decision-parameters/change-decision-parameters.component';
import { VoteProgressOngoingComponent } from './page/shares/voting/vote-progress-ongoing/vote-progress-ongoing.component';
import { VoteCountOngoingComponent } from './page/shares/voting/vote-count-ongoing/vote-count-ongoing.component';
import { SummaryComponent } from './page/shares/summary/summary.component';
import { DecisionParametersComponent } from './page/shares/decision-parameters/decision-parameters.component';
import { VoteDetailsChangeDecisionParametersComponent } from './page/shares/voting/vote-details-change-decision-parameters/vote-details-change-decision-parameters.component';

@NgModule({
  declarations: [
    AppComponent,
    SeedtokensComponent,
    SharesComponent,
    ExchangeComponent,
    NewTokenComponent,
    ProgressSpinnerOverlayComponent,
    MintComponent,
    ChangeOwnerComponent,
    NewShareComponent,
    ChangeDecisionParametersComponent,
    VoteProgressOngoingComponent,
    VoteCountOngoingComponent,
    SummaryComponent,
    DecisionParametersComponent,
    VoteDetailsChangeDecisionParametersComponent
  ],
  imports: [
    BrowserModule,
    AppRoutingModule,
    BrowserAnimationsModule,
    FormsModule,
    HttpClientModule,
    MaterialDesignModule
  ],
  providers: [],
  bootstrap: [AppComponent]
})
export class AppModule {
  constructor(matIconRegistry: MatIconRegistry, domSanitizer: DomSanitizer){
    matIconRegistry.addSvgIconSet(
      domSanitizer.bypassSecurityTrustResourceUrl('./assets/mdi.svg')
    );
  }
}
