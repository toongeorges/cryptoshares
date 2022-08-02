import { Component, Input, OnInit } from '@angular/core';
import { MatDialog } from '@angular/material/dialog';
import { MatTableDataSource } from '@angular/material/table';
import { EthersService } from 'src/app/services/ethers.service';
import { ChangeDecisionParametersComponent } from '../dialogs/change-decision-parameters/change-decision-parameters.component';
import { DecisionParameters } from '../shares.component';

@Component({
  selector: 'app-decision-parameters',
  templateUrl: './decision-parameters.component.html',
  styleUrls: ['./decision-parameters.component.scss']
})
export class DecisionParametersComponent implements OnInit {
  public actionColumns: string[] = [ 'name', 'isDefault', 'decisionTime', 'executionTime', 'quorum', 'majority', 'actions' ];
  public isHideDefault = false;

  @Input('decisionParameters') public decisionParameters: MatTableDataSource<DecisionParameters>;
  @Input('isValidAction') isValidAction: boolean;
  @Input('onDialogClose') onDialogClose: () => void;
  @Input('formatSeconds') formatSeconds: any;

  constructor(
    public ethersService: EthersService,
    private dialog: MatDialog
  ) { }

  ngOnInit(): void {
  }

  toggleShowDefault() {
    this.isHideDefault = !this.isHideDefault;
    this.decisionParameters.filter = this.isHideDefault ? 'hide' : '';
  }

  openChangeDecisionParametersDialog(dP: DecisionParameters): void {
    const clone = {... dP};
    clone.onDialogClose = this.onDialogClose;
    this.dialog.open(ChangeDecisionParametersComponent, {
      data: clone
    });
  }
}
