import { Component, Inject, OnInit } from '@angular/core';
import { MatDialogRef, MAT_DIALOG_DATA } from '@angular/material/dialog';
import { NewToken } from '../seedtokens.component';
import { EthersService } from 'src/app/services/ethers.service';

@Component({
  selector: 'app-new-token',
  templateUrl: './new-token.component.html',
  styleUrls: ['./new-token.component.scss']
})
export class NewTokenComponent implements OnInit {
  constructor(
    @Inject(MAT_DIALOG_DATA) public data: NewToken,
    private dialogRef: MatDialogRef<NewTokenComponent>,
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
      this.ethersService.getConnectedSeedTokenFactory()['create'](this.data.name, this.data.symbol, {
        gasLimit: 2000000
      }),
      this.data.onDialogClose
    );
  }
}