import { Component, Inject, OnInit } from '@angular/core';
import { MatDialogRef, MAT_DIALOG_DATA } from '@angular/material/dialog';
import { EthersService } from 'src/app/services/ethers.service';
import { ChangeOwner } from '../seedtokens.component';

@Component({
  selector: 'app-change-owner',
  templateUrl: './change-owner.component.html',
  styleUrls: ['./change-owner.component.scss']
})
export class ChangeOwnerComponent implements OnInit {
  displayedColumns: string[] = [ 'key', 'value' ];
  dataSource: { key: string; value: string; }[] = [];

  constructor(
    @Inject(MAT_DIALOG_DATA) public data: ChangeOwner,
    private dialogRef: MatDialogRef<ChangeOwnerComponent>,
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

  onChangeOwner() {
    this.dialogRef.close();
    this.ethersService.showProgressSpinnerUntilExecuted(
      this.ethersService.connect(this.data.token)['changeOwner'](this.data.newOwner, {
        gasLimit: 50000
      }),
      this.data.onDialogClose
    );
  }
}
