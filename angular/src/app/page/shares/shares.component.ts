import { AfterViewInit, Component, OnInit, ViewChild } from '@angular/core';
import { MatDialog } from '@angular/material/dialog';
import { MatPaginator } from '@angular/material/paginator';
import { MatSort } from '@angular/material/sort';
import { MatTableDataSource } from '@angular/material/table';
import { ethers } from "ethers";
import { EthersService } from 'src/app/services/ethers.service';
import * as shareData from '../../../../../solidity/artifacts/contracts/Share.sol/Share.json';
import { NewShareComponent } from './new-share/new-share.component';

@Component({
  selector: 'app-shares',
  templateUrl: './shares.component.html',
  styleUrls: ['./shares.component.scss']
})
export class SharesComponent implements OnInit, AfterViewInit {
  public displayedColumns: string[] = ['name', 'symbol'];
  public userAddress: string = '';
  public numberOfShares: number;
  public dataSource: MatTableDataSource<Share>;
  public contracts: ethers.Contract[];
  public selected: Share;
  public summaryColumns: string[] = [ 'key', 'value' ];
  public summary: { key: string; value: string; }[] = [];
  public actions = [
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
  public actionColumns: string[] = [ 'name', 'decisionTime', 'executionTime', 'quorum', 'majority' ];
  public decisionParameters: MatTableDataSource<DecisionParameters>;

  private shares: Share[];

  @ViewChild(MatPaginator) paginator: MatPaginator;
  @ViewChild(MatSort) sort: MatSort;

  constructor(
    private ethersService: EthersService,
    private dialog: MatDialog
  ) { }

  init() {
    this.numberOfShares = 0;
    this.shares = [];
    this.dataSource = new MatTableDataSource(this.shares);
    this.contracts = [];
  }

  ngOnInit(): void {
    this.init(); //reinitialize after closing a dialog

    this.ethersService.provider.getSigner().getAddress().then((userAddress: string) => {
      this.userAddress = userAddress;
      return this.ethersService.shareFactory['getNumberOfShares']();
    }).then(async (numberOfShares: number) => {
      this.numberOfShares = numberOfShares;

      for (let i = 0; i < numberOfShares; i++) {
        let shareAddress = await this.ethersService.shareFactory['shares'](i);
  
        let contract = new ethers.Contract(
          shareAddress,
          (shareData as any).default.abi,
          this.ethersService.provider
        );
        this.contracts.push(contract);
  
        const name = await contract['name']();
        const symbol = await contract['symbol']();
        const supply = await contract['totalSupply']();
        const balance = await contract['balanceOf'](this.userAddress);
        const owner = await contract['owner']();
        const exchange = await contract['exchange']();
        const numberOfShareholders = await contract['getShareholderCount']();
        const numberOfProposals = await contract['getNumberOfProposals']();
  
        this.shares.push({
          index: i,
          name: name,
          symbol: symbol,
          supply: supply,
          balance: balance,
          owner: owner,
          exchange: exchange,
          numberOfShareholders: numberOfShareholders,
          numberOfProposals: numberOfProposals
        });
  
        this.dataSource = new MatTableDataSource(this.shares);
        this.dataSource.paginator = this.paginator;
        this.dataSource.sort = this.sort;
      }
    });
  }

  ngAfterViewInit() {
    this.dataSource.paginator = this.paginator;
    this.dataSource.sort = this.sort;
  }

  getProgress(): number {
    return (this.numberOfShares == 0) ? 0 : 100*this.shares.length/this.numberOfShares;
  }

  applyFilter(event: Event) {
    const filterValue = (event.target as HTMLInputElement).value;
    this.dataSource.filter = filterValue.trim().toLowerCase();
  }

  select(share: Share) {
    this.selected = share;
    this.summary = [];
    this.summary.push({
      key: 'Address',
      value: this.contracts[share.index].address
    });
    this.summary.push({
      key: 'Symbol',
      value: share.symbol
    });
    this.summary.push({
      key: 'Supply',
      value: share.supply
    });
    this.summary.push({
      key: 'Balance',
      value: share.balance
    });
    this.summary.push({
      key: 'Owner',
      value: share.owner
    });
    this.summary.push({
      key: 'Exchange',
      value: share.exchange
    });
    this.summary.push({
      key: '# Shareholders',
      value: share.numberOfShareholders
    });
    this.summary.push({
      key: '# Proposals',
      value: share.numberOfProposals
    });

    this.updateDecisionParameters(this.selected.index);
  }

  async updateDecisionParameters(selectedIndex: number) {
    let decisionParameters = [];
    
    const contract = this.contracts[selectedIndex];
    for (let i = 0; i < this.actions.length; i++) {
      const dP: any[] = await contract['getDecisionParameters'](i);
      decisionParameters.push({
        index: i,
        decisionTime: this.formatSeconds(dP[0]),
        executionTime: this.formatSeconds(dP[1]),
        quorum: dP[2] + '/' + dP[3],
        majority: dP[4] + '/' + dP[5]
      });
    }

    this.decisionParameters = new MatTableDataSource(decisionParameters);
  }

  formatSeconds(remaining: number): string {
    const s = remaining%60;
    remaining = Math.floor(remaining/60);
    const m = remaining%60;
    remaining = Math.floor(remaining/60);
    const h = remaining%24;
    remaining = Math.floor(remaining/24);

    let returnValue = '';
    if (remaining != 0) {
      returnValue = remaining + 'd';
    }
    if (h != 0) {
      returnValue += h + 'h';
    }
    if (m != 0) {
      returnValue += m + 'm';
    }
    if (s != 0) {
      returnValue += s + 's';
    }

    return returnValue;
  }

  openNewShareDialog(): void {
    this.dialog.open(NewShareComponent, {
      data: {
        name: '',
        symbol: '',
        numberOfShares: '',
        exchangeAddress: '',
        decisionTime: '2592000', //30 days
        executionTime: '604800', //7 days
        quorumNumerator: '0',
        quorumDenominator: '1',
        majorityNumerator: '1',
        majorityDenominator: '2',
        onDialogClose: () => { this.ngOnInit(); }
      }
    });
  }
}

export interface Share {
  index: number;
  name: string;
  symbol: string;
  supply: string;
  balance: string;
  owner: string;
  exchange: string;
  numberOfShareholders: string;
  numberOfProposals: string;
}

export interface NewShare {
  name: string;
  symbol: string;
  numberOfShares: string;
  exchangeAddress: string;
  decisionTime: string;
  executionTime: string;
  quorumNumerator: string;
  quorumDenominator: string;
  majorityNumerator: string;
  majorityDenominator: string;
  onDialogClose: any;
}

export class DecisionParameters {
  index: number;
  decisionTime: string;
  executionTime: string;
  quorum: string;
  majority: string;
}
