import { Injectable } from '@angular/core';
import { ethers } from "ethers";
import * as exchangeData from '../../../../solidity/artifacts/contracts/Exchange.sol/Exchange.json';

@Injectable({
  providedIn: 'root'
})
export class EthersService {
  public version: string;
  public provider: ethers.providers.Web3Provider;

  public exchangeAddress: string = '0x5FbDB2315678afecb367f032d93F642f64180aa3';
  public exchange: ethers.Contract;

  constructor() {
    this.version = ethers.version;
    this.provider = new ethers.providers.Web3Provider((window as any).ethereum);
    this.exchange = new ethers.Contract(this.exchangeAddress, (exchangeData as any).default.abi, this.provider);
  }
}
