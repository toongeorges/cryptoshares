import { Injectable } from '@angular/core';
import { ethers } from "ethers";
import * as seedTokenFactoryData from '../../../../solidity/artifacts/contracts/SeedTokenFactory.sol/SeedTokenFactory.json';
import * as exchangeData from '../../../../solidity/artifacts/contracts/Exchange.sol/Exchange.json';
import { MatDialog, MatDialogRef } from '@angular/material/dialog';
import { ProgressSpinnerOverlayComponent } from '../page/progress-spinner-overlay/progress-spinner-overlay.component';

@Injectable({
  providedIn: 'root'
})
export class EthersService {
  public version: string;
  public provider: ethers.providers.Web3Provider;

  public seedTokenFactoryAddress: string = '0x5FbDB2315678afecb367f032d93F642f64180aa3';
  public seedTokenFactory: ethers.Contract;

  public exchangeAddress: string = '0x0165878A594ca255338adfa4d48449f69242Eb8F';
  public exchange: ethers.Contract;

  constructor(private dialog: MatDialog) {
    this.version = ethers.version;
    this.provider = new ethers.providers.Web3Provider((window as any).ethereum);
    this.seedTokenFactory = new ethers.Contract(this.seedTokenFactoryAddress, (seedTokenFactoryData as any).default.abi, this.provider);
    this.exchange = new ethers.Contract(this.exchangeAddress, (exchangeData as any).default.abi, this.provider);
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

  connect(contract: ethers.Contract) {
    return contract.connect(this.provider.getSigner());
  }
}
