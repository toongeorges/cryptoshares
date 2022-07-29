import { AfterViewInit, Component, OnInit, ViewChild } from '@angular/core';
import { MatDialog } from '@angular/material/dialog';
import { MatPaginator } from '@angular/material/paginator';
import { MatSort } from '@angular/material/sort';
import { MatTableDataSource } from '@angular/material/table';
import { ethers } from "ethers";
import { EthersService } from 'src/app/services/ethers.service';
import * as shareData from '../../../../../solidity/artifacts/contracts/Share.sol/Share.json';
import { ChangeDecisionParametersComponent } from './change-decision-parameters/change-decision-parameters.component';
import { NewShareComponent } from './new-share/new-share.component';

@Component({
  selector: 'app-shares',
  templateUrl: './shares.component.html',
  styleUrls: ['./shares.component.scss']
})
export class SharesComponent implements OnInit, AfterViewInit {
  public displayedColumns: string[] = ['name', 'symbol'];
  public dataSource: MatTableDataSource<Share>;

  public userAddress: string = '';
  public numberOfShares: number;
  public contracts: ethers.Contract[];

  public selected: Share;

  public summaryColumns: string[] = [ 'key', 'value' ];
  public summary: { key: string; value: string; }[] = [];

  public pendingRequestId = 0;
  public voteInformationColumns: string[] = [ 'key', 'value' ];
  public voteInformation: { key: string; value: string; }[] = [];

  public actionColumns: string[] = [ 'name', 'isDefault', 'decisionTime', 'executionTime', 'quorum', 'majority', 'actions' ];
  public decisionParameters: MatTableDataSource<DecisionParameters>;
  public isHideDefault = false;

  private shares: Share[];

  @ViewChild(MatPaginator) paginator: MatPaginator;
  @ViewChild(MatSort) sort: MatSort;

  constructor(
    public ethersService: EthersService,
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
    }).then((numberOfShares: number) => {
      this.numberOfShares = numberOfShares;

      for (let i = 0; i < numberOfShares; i++) {
        this.pushShare(i);
      }
    });
  }

  async getShare(i: number): Promise<Share> {
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

    return {
      index: i,
      name: name,
      symbol: symbol,
      supply: supply,
      balance: balance,
      owner: owner,
      exchange: exchange,
      numberOfShareholders: numberOfShareholders,
      numberOfProposals: numberOfProposals
    };
  }

  pushShare(i: number) {
    this.getShare(i).then((share: Share) => {
      this.shares.push(share);

      this.dataSource = new MatTableDataSource(this.shares);
      this.dataSource.paginator = this.paginator;
      this.dataSource.sort = this.sort;
    });
  }

  addShare() {
    this.pushShare(this.numberOfShares);
    this.numberOfShares++;
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
    this.updateSummary(share);
    this.updateDecisionParameters();
  }

  updateSummary(share: Share) {
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
  }

  async updateDecisionParameters() {
    let decisionParameters = [];
    
    const contract = this.contracts[this.selected.index];

    this.pendingRequestId = await contract['pendingRequestId']();

    if (this.pendingRequestId != 0) {
      this.updateVoteInformation(contract);
    }

    for (let i = 0; i < this.ethersService.shareActions.length; i++) {
      const dP: any[] = await contract['getDecisionParameters'](i);
      if (!this.isHideDefault || !dP[0]) {
        decisionParameters.push({
          index: i,
          isDefault: dP[0],
          decisionTime: dP[1],
          executionTime: dP[2],
          quorumNumerator: dP[3],
          quorumDenominator: dP[4],
          majorityNumerator: dP[5],
          majorityDenominator: dP[6],
          contract: contract,
          onDialogClose: null
        });
      }
    }

    this.decisionParameters = new MatTableDataSource(decisionParameters);
  }

  updateVoteInformation(contract: ethers.Contract) {
    let vote: Vote = {
      voteType: 0,
      start: new Date(Date.UTC(1970, 0, 1)),
      decisionEnd: new Date(Date.UTC(1970, 0, 1)),
      executionEnd: new Date(Date.UTC(1970, 0, 1)),
      quorumNumerator: '',
      quorumDenominator: '',
      majorityNumerator: '',
      majorityDenominator: '',
      numberOfVotes: '',
    };

    contract['getProposalDecisionParameters'](this.pendingRequestId).then((dP: any[]) => {
      console.dir(dP);
      vote.voteType = dP[0];
      vote.quorumNumerator = dP[3];
      vote.quorumDenominator = dP[4];
      vote.majorityNumerator = dP[5];
      vote.majorityDenominator = dP[6];
      return contract['getProposalDecisionTimes'](this.pendingRequestId);
    }).then((dT: any[]) => {
      console.dir(dT);
      vote.start.setUTCSeconds(dT[0]);
      vote.decisionEnd.setUTCSeconds(dT[1]);
      vote.executionEnd.setUTCSeconds(dT[2]);
      return contract['getNumberOfVotes'](this.pendingRequestId);
    }).then((numberOfVotes: string) => {
      console.dir(numberOfVotes);
      vote.numberOfVotes = numberOfVotes;

      this.voteInformation = [];
      this.voteInformation.push({
        key: 'Vote Type',
        value: this.ethersService.shareActions[vote.voteType]
      });
      this.voteInformation.push({
        key: 'Start Time',
        value: vote.start.toString()
      });
      this.voteInformation.push({
        key: 'Decision End Time',
        value: vote.decisionEnd.toString()
      });
      this.voteInformation.push({
        key: 'Execution End Time',
        value: vote.executionEnd.toString()
      });
      this.voteInformation.push({
        key: 'Quorum',
        value: vote.quorumNumerator + '/' + vote.quorumDenominator
      });
      this.voteInformation.push({
        key: 'Majority',
        value: vote.majorityNumerator + '/' + vote.majorityDenominator
      });
      this.voteInformation.push({
        key: '# Votes',
        value: vote.numberOfVotes
      });
    });
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

  isValidAction(): boolean {
    return (this.pendingRequestId == 0) && (this.selected.owner == this.userAddress);
  }

  toggleShowDefault() {
    this.isHideDefault = !this.isHideDefault;
    this.updateDecisionParameters();
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
        onDialogClose: () => { this.addShare(); }
      }
    });
  }

  openChangeDecisionParametersDialog(dP: DecisionParameters): void {
    const clone = {... dP};
    clone.onDialogClose = () => { this.select(this.selected); };
    this.dialog.open(ChangeDecisionParametersComponent, {
      data: clone
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
  isDefault: boolean;
  decisionTime: string;
  executionTime: string;
  quorumNumerator: string;
  quorumDenominator: string;
  majorityNumerator: string;
  majorityDenominator: string;
  contract: ethers.Contract;
  onDialogClose: any;
}

export class Vote {
  voteType: number;
  start: Date;
  decisionEnd: Date;
  executionEnd: Date;
  quorumNumerator: string;
  quorumDenominator: string;
  majorityNumerator: string;
  majorityDenominator: string;
  numberOfVotes: string;
}