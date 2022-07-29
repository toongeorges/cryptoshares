import { Component, Inject, OnInit } from '@angular/core';
import { MatDialogRef, MAT_DIALOG_DATA } from '@angular/material/dialog';
import { ethers } from "ethers";
import { EthersService } from 'src/app/services/ethers.service';
import { DecisionParameters } from '../shares.component';

@Component({
  selector: 'app-change-decision-parameters',
  templateUrl: './change-decision-parameters.component.html',
  styleUrls: ['./change-decision-parameters.component.scss']
})
export class ChangeDecisionParametersComponent implements OnInit {
  constructor(
    @Inject(MAT_DIALOG_DATA) public data: DecisionParameters,
    private dialogRef: MatDialogRef<ChangeDecisionParametersComponent>,
    public ethersService: EthersService
  ) {}

  ngOnInit(): void {
  }

  onCancel() {
    this.dialogRef.close();
  }

  onChange() {
    this.dialogRef.close();
    this.ethersService.showProgressSpinnerUntilExecuted(
      this.ethersService.connect(this.data.contract)['changeDecisionParameters'](
        this.data.index,
        ethers.BigNumber.from(this.data.decisionTime),
        ethers.BigNumber.from(this.data.executionTime),
        ethers.BigNumber.from(this.data.quorumNumerator),
        ethers.BigNumber.from(this.data.quorumDenominator),
        ethers.BigNumber.from(this.data.majorityNumerator),
        ethers.BigNumber.from(this.data.majorityDenominator), {
          gasLimit: 500000
        }
      ),
      this.data.onDialogClose
    );
  }
}
