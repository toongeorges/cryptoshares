import { Component, Inject, OnInit } from '@angular/core';
import { MatDialogRef, MAT_DIALOG_DATA } from '@angular/material/dialog';
import { ethers } from "ethers";
import { EthersService } from 'src/app/services/ethers.service';
import { MintAmount } from '../seedtokens.component';

@Component({
  selector: 'app-mint',
  templateUrl: './mint.component.html',
  styleUrls: ['./mint.component.scss']
})
export class MintComponent implements OnInit {
  displayedColumns: string[] = [ 'key', 'value' ];
  dataSource: { key: string; value: string; }[] = [];

  constructor(
    @Inject(MAT_DIALOG_DATA) public data: MintAmount,
    private dialogRef: MatDialogRef<MintComponent>,
    private ethersService: EthersService
  ) {}

  ngOnInit(): void {
    this.dataSource.push({
      key: 'Address',
      value: this.data.token.address
    });
    this.dataSource.push({
      key: 'Name',
      value: this.data.name
    });
    this.dataSource.push({
      key: 'Symbol',
      value: this.data.symbol
    });
  }

  onCancel() {
    this.dialogRef.close();
  }

  onMint() {
    this.dialogRef.close();
    this.ethersService.showProgressSpinnerUntilExecuted(
      this.ethersService.connect(this.data.token)['mint'](ethers.BigNumber.from(this.data.amount), {
        gasLimit: 100000
      }),
      this.data.onDialogClose
    );
  }
}
