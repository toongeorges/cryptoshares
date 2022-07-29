import { Injectable } from '@angular/core';
import { MatDialog, MatDialogRef } from '@angular/material/dialog';
import { ProgressSpinnerOverlayComponent } from '../page/progress-spinner-overlay/progress-spinner-overlay.component';
import { ethers } from "ethers";
import * as seedTokenFactoryData from '../../../../solidity/artifacts/contracts/SeedTokenFactory.sol/SeedTokenFactory.json';
import * as exchangeData from '../../../../solidity/artifacts/contracts/Exchange.sol/Exchange.json';
import * as shareFactoryData from '../../../../solidity/artifacts/contracts/ShareFactory.sol/ShareFactory.json';

@Injectable({
  providedIn: 'root'
})
export class EthersService {
  public version: string;
  public provider: ethers.providers.Web3Provider;

  public seedTokenFactoryAddress: string = '0x5FbDB2315678afecb367f032d93F642f64180aa3';
  public seedTokenFactory: ethers.Contract;

  public exchangeAddress: string = '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512';
  public exchange: ethers.Contract;

  public shareFactoryAddress: string = '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0';
  public shareFactory: ethers.Contract;

  public shareActions = [
    'Default',
    'Change Owner',
    'Change Decision Parameters',
    'Issue Shares',
    'Destroy Shares',
    'Withdraw Funds',
    'Change Exchange',
    'Ask',
    'Bid',
    'Cancel Order',
    'Reverse Split',
    'Distribute Dividend',
    'Distribute Optional Dividend',
    'External Proposal Default'
  ];

  constructor(private dialog: MatDialog) {
    this.version = ethers.version;
    this.provider = new ethers.providers.Web3Provider((window as any).ethereum);
    this.seedTokenFactory = new ethers.Contract(this.seedTokenFactoryAddress, (seedTokenFactoryData as any).default.abi, this.provider);
    this.exchange = new ethers.Contract(this.exchangeAddress, (exchangeData as any).default.abi, this.provider);
    this.shareFactory = new ethers.Contract(this.shareFactoryAddress, (shareFactoryData as any).default.abi, this.provider);
  }

  showProgressSpinnerUntilExecuted(promise: Promise<any>, onDialogClose: any) {
    let progressSpinnerRef: MatDialogRef<ProgressSpinnerOverlayComponent> = this.dialog.open(ProgressSpinnerOverlayComponent, {
      panelClass: 'transparent',
      disableClose: true
    });
    promise.then((response) => response.wait())
    .then(() => {
      progressSpinnerRef.close();
      onDialogClose();
    }).catch((error) => {
      console.log(error.message);
      progressSpinnerRef.close();
    });
  }

  getConnectedSeedTokenFactory(): ethers.Contract {
    return this.connect(this.seedTokenFactory);
  }

  getConnectedExchange(): ethers.Contract {
    return this.connect(this.exchange);
  }

  getConnectedShareFactory(): ethers.Contract {
    return this.connect(this.shareFactory);
  }

  connect(contract: ethers.Contract) {
    return contract.connect(this.provider.getSigner());
  }
}
