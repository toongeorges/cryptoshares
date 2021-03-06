import { AfterViewInit, Component, OnInit, ViewChild } from '@angular/core';
import { MatDialog } from '@angular/material/dialog';
import { MatPaginator } from '@angular/material/paginator';
import { MatSort } from '@angular/material/sort';
import { MatTableDataSource } from '@angular/material/table';
import { ethers } from "ethers";
import { EthersService } from 'src/app/services/ethers.service';
import * as seedTokenData from '../../../../../solidity/artifacts/contracts/SeedToken.sol/SeedToken.json';
import { ChangeOwnerComponent } from './change-owner/change-owner.component';
import { MintComponent } from './mint/mint.component';
import { NewTokenComponent } from './new-token/new-token.component';

@Component({
  selector: 'app-seedtokens',
  templateUrl: './seedtokens.component.html',
  styleUrls: ['./seedtokens.component.scss']
})
export class SeedtokensComponent implements OnInit, AfterViewInit {
  public displayedColumns: string[] = ['name', 'symbol', 'supply', 'balance', 'mint', 'owner'];
  public userAddress: string = '';
  public numberOfTokens: number;
  public dataSource: MatTableDataSource<SeedToken>;
  public contracts: ethers.Contract[];

  private seedTokens: SeedToken[];

  @ViewChild(MatPaginator) paginator: MatPaginator;
  @ViewChild(MatSort) sort: MatSort;

  constructor(
    private ethersService: EthersService,
    private dialog: MatDialog
  ) {
    this.init();
  }

  init() {
    this.numberOfTokens = 0;
    this.seedTokens = [];
    this.dataSource = new MatTableDataSource(this.seedTokens);
    this.contracts = [];
  }

  ngOnInit(): void {
    this.init(); //reinitialize after closing a dialog

    this.ethersService.provider.getSigner().getAddress().then((userAddress: string) => {
      this.userAddress = userAddress;
      return this.ethersService.seedTokenFactory['getNumberOfTokens']();
    }).then(async (numberOfTokens: number) => {
      this.numberOfTokens = numberOfTokens;

      for (let i = 0; i < numberOfTokens; i++) {
        await this.pushToken(i);
      }
    });
  }

  async getToken(i: number): Promise<SeedToken> {
    const seedTokenAddress = await this.ethersService.seedTokenFactory['tokens'](i);

    const contract = new ethers.Contract(
      seedTokenAddress,
      (seedTokenData as any).default.abi,
      this.ethersService.provider
    );
    this.contracts.push(contract);

    const name = await contract['name']();
    const symbol = await contract['symbol']();
    const decimals = await contract['decimals']();
    let supply = await contract['totalSupply']();
    supply = ethers.BigNumber.from(supply).div(ethers.BigNumber.from('10').pow(decimals));
    let balance = await contract['balanceOf'](this.userAddress);
    balance = ethers.BigNumber.from(balance).div(ethers.BigNumber.from('10').pow(decimals));
    const owner = await contract['owner']();

    return {
      index: i,
      name: name,
      symbol: symbol,
      supply: supply,
      balance: balance,
      owner: owner
    };
  }

  pushToken(i: number) {
    this.getToken(i).then((token: SeedToken) => {
      this.seedTokens.push(token);

      this.dataSource = new MatTableDataSource(this.seedTokens);
      this.dataSource.paginator = this.paginator;
      this.dataSource.sort = this.sort;
    });
  }

  refreshToken(i: number) {
    this.getToken(i).then((token: SeedToken) => {
      this.seedTokens[i] = token

      this.dataSource = new MatTableDataSource(this.seedTokens);
      this.dataSource.paginator = this.paginator;
      this.dataSource.sort = this.sort;
    });
  }

  addToken() {
    this.pushToken(this.numberOfTokens);
    this.numberOfTokens++;
  }

  ngAfterViewInit() {
    this.dataSource.paginator = this.paginator;
    this.dataSource.sort = this.sort;
  }

  getProgress(): number {
    return (this.numberOfTokens == 0) ? 0 : 100*this.seedTokens.length/this.numberOfTokens;
  }

  applyFilter(event: Event) {
    const filterValue = (event.target as HTMLInputElement).value;
    this.dataSource.filter = filterValue.trim().toLowerCase();
  }

  openNewTokenDialog(): void {
    this.dialog.open(NewTokenComponent, {
      data: {
        name: '',
        symbol: '',
        onDialogClose: () => { this.addToken(); }
      }
    });
  }

  openMintDialog(token: ethers.Contract, name: string, symbol: string, index: number): void {
    this.dialog.open(MintComponent, {
      data: {
        token: token,
        name: name,
        symbol: symbol,
        amount: '',
        onDialogClose: () => { this.refreshToken(index); }
      }
    });
  }

  openChangeOwnerDialog(token: ethers.Contract, name: string, symbol: string, index: number): void {
    this.dialog.open(ChangeOwnerComponent, {
      data: {
        token: token,
        name: name,
        symbol: symbol,
        newOwner: '',
        onDialogClose: () => { this.refreshToken(index); }
      }
    });
  }
}

export interface SeedToken {
  index: number;
  name: string;
  symbol: string;
  supply: string;
  balance: string;
  owner: string;
}

export interface NewToken {
  name: string;
  symbol: string;
  onDialogClose: any;
}

export interface MintAmount {
  token: ethers.Contract;
  name: string;
  symbol: string;
  amount: string;
  onDialogClose: any;
}

export interface ChangeOwner {
  token: ethers.Contract;
  name: string;
  symbol: string;
  newOwner: string;
  onDialogClose: any;
}
