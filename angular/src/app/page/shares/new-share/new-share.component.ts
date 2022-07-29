import { Component, Inject, OnInit } from '@angular/core';
import { MatDialogRef, MAT_DIALOG_DATA } from '@angular/material/dialog';
import { ethers } from "ethers";
import { EthersService } from 'src/app/services/ethers.service';
import { NewShare } from '../shares.component';

@Component({
  selector: 'app-new-share',
  templateUrl: './new-share.component.html',
  styleUrls: ['./new-share.component.scss']
})
export class NewShareComponent implements OnInit {
  constructor(
    @Inject(MAT_DIALOG_DATA) public data: NewShare,
    private dialogRef: MatDialogRef<NewShareComponent>,
    private ethersService: EthersService
  ) {}

  ngOnInit(): void {
  }

  onCancel() {
    this.dialogRef.close();
  }

  onCreate() {
    this.dialogRef.close();
    this.ethersService.showProgressSpinnerUntilExecuted(
      this.ethersService.getConnectedShareFactory()['create'](
        this.data.name,
        this.data.symbol,
        ethers.BigNumber.from(this.data.numberOfShares),
        [
          ethers.BigNumber.from(this.data.decisionTime),
          ethers.BigNumber.from(this.data.executionTime),
          ethers.BigNumber.from(this.data.quorumNumerator),
          ethers.BigNumber.from(this.data.quorumDenominator),
          ethers.BigNumber.from(this.data.majorityNumerator),
          ethers.BigNumber.from(this.data.majorityDenominator)
        ],
        this.data.exchangeAddress, {
          gasLimit: 5000000
        }
      ),
      this.data.onDialogClose
    );
  }
}
