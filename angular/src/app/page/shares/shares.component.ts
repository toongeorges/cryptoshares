import { AfterViewInit, Component, OnDestroy, OnInit, ViewChild } from '@angular/core';
import { MatDialog } from '@angular/material/dialog';
import { MatPaginator } from '@angular/material/paginator';
import { MatSort } from '@angular/material/sort';
import { MatTableDataSource } from '@angular/material/table';
import { ethers } from "ethers";
import { interval, Subscription } from 'rxjs';
import { EthersService } from 'src/app/services/ethers.service';
import * as shareData from '../../../../../solidity/artifacts/contracts/Share.sol/Share.json';
import { NewShareComponent } from './dialogs/new-share/new-share.component';

@Component({
  selector: 'app-shares',
  templateUrl: './shares.component.html',
  styleUrls: ['./shares.component.scss']
})
export class SharesComponent implements OnInit, AfterViewInit, OnDestroy {
  public displayedColumns: string[] = ['name', 'symbol'];
  public dataSource: MatTableDataSource<Share>;

  public userAddress: string = '';
  public numberOfShares: number;
  public contracts: ethers.Contract[];

  public selected: Share;

  public summary: { key: string; value: string; }[] = [];

  public pendingRequestId = 0;
  public vote: Vote;

  public decisionParameters: MatTableDataSource<DecisionParameters>;

  private shares: Share[];
  private countDown: Subscription;

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

    this.countDown = interval(1000).subscribe(() => { this.updateTimes(); });
  }

  ngOnDestroy(): void {
    this.countDown.unsubscribe();
  }

  async getShare(i: number): Promise<Share> {
    const shareAddress = await this.ethersService.shareFactory['shares'](i);
  
    const contract = new ethers.Contract(
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

  async getDecisionParameters(i: number): Promise<DecisionParameters[]> {
    const contract = this.contracts[i];

    let decisionParameters = [];
    
    for (let i = 0; i < this.ethersService.shareActions.length; i++) {
      const dP: any[] = await contract['getDecisionParameters'](i);
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
        onDialogClose: () => {}
      });
    }

    return decisionParameters;
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
    this.getShare(share.index).then((refreshedShare) => {
      this.selected = refreshedShare;
      this.updateSummary(refreshedShare);

      return this.getDecisionParameters(share.index);
    }).then((decisionParameters: DecisionParameters[]) => {
      this.decisionParameters = new MatTableDataSource(decisionParameters);
      this.decisionParameters.filterPredicate = (dP: DecisionParameters, filter: string) => !filter || !dP.isDefault; 

      return this.contracts[share.index]['pendingRequestId']();
    }).then((pendingRequestId: number) => {
      this.pendingRequestId = pendingRequestId;

      if (this.pendingRequestId != 0) {
        //if we do not connect the contract, we will e.g. not be able to retrieve the vote choice!
        const contract = this.ethersService.connect(this.contracts[this.selected.index]);

        this.updateVoteInformation(contract);
      }
    });
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
      value: share.supply.toString()
    });
    this.summary.push({
      key: 'Balance',
      value: share.balance.toString()
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

  updateVoteInformation(contract: ethers.Contract) {
    let vote: Vote = {
      voteType: 0,
      start: 0,
      decisionEnd: 0,
      decisionRemaining: 0,
      decisionTimeProgress: 0,
      executionEnd: 0,
      executionRemaining: 0,
      executionTimeProgress: 0,
      stage: 0,
      quorumNumerator: 0,
      quorumDenominator: 1,
      majorityNumerator: 1,
      majorityDenominator: 2,
      numberOfVotes: '',
      result: 0,
      inFavor: ethers.BigNumber.from(0),
      against: ethers.BigNumber.from(0),
      abstain: ethers.BigNumber.from(0),
      noVote: ethers.BigNumber.from(0),
      choice: -1
    };

    this.vote = vote;

    contract['getDetailedVoteResult'](this.pendingRequestId).then((vR: any[]) => {
      vote.result = vR[0];
      vote.inFavor = vR[1];
      vote.against = vR[2];
      vote.abstain = vR[3];
      vote.noVote = vR[4];

      return contract['getProposalDecisionParameters'](this.pendingRequestId);
    }).then((dP: any[]) => {
      vote.voteType = dP[0];
      vote.quorumNumerator = dP[3];
      vote.quorumDenominator = dP[4];
      vote.majorityNumerator = dP[5];
      vote.majorityDenominator = dP[6];

      return contract['getProposalDecisionTimes'](this.pendingRequestId);
    }).then((dT: any[]) => {
      vote.start = dT[0];
      vote.decisionEnd = dT[1];
      vote.executionEnd = dT[2];

      return contract['getNumberOfVotes'](this.pendingRequestId);
    }).then((numberOfVotes: string) => {
      vote.numberOfVotes = numberOfVotes;

      return contract['getVoteChoice'](this.pendingRequestId);
    }).then((choice: any) => {
      vote.choice = choice;
    });
  }

  updateTimes() {
    if (this.vote && this.vote.result == 1) {
      const vote = this.vote;
      const now = new Date().getTime()/1000;
  
      if (now < vote.start) {
        vote.decisionRemaining = vote.decisionEnd - now;
        vote.decisionTimeProgress = 0;
        vote.executionRemaining = vote.executionEnd - now;
        vote.executionTimeProgress = 0;
        vote.stage = 0;
      } else if (now < vote.decisionEnd) {
        vote.decisionRemaining = vote.decisionEnd - now;
        vote.decisionTimeProgress = 100*(now - vote.start)/(vote.decisionEnd - vote.start);
        vote.executionRemaining = vote.executionEnd - now;
        vote.executionTimeProgress = 0;
        vote.stage = 0;
      } else if (now < vote.executionEnd) {
        vote.decisionRemaining = 0;
        vote.decisionTimeProgress = 100;
        vote.executionRemaining = vote.executionEnd - now;
        vote.executionTimeProgress = 100*(now - vote.decisionEnd)/(vote.executionEnd - vote.decisionEnd);
        vote.stage = 1;
      } else {
        vote.decisionRemaining = 0;
        vote.decisionTimeProgress = 100;
        vote.executionRemaining = 0;
        vote.executionTimeProgress = 100;
        vote.stage = 2;
      }
    }
  }

  formatSeconds(remaining: number): string {
    const s = Math.floor(remaining%60);
    remaining = Math.floor(remaining/60);
    if (remaining <= 0) {
      return s + 's';
    }
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

  getSelectedContract(): ethers.Contract {
    return this.contracts[this.selected.index];
  }

  refreshSelected(): () => void {
    return () => { this.select(this.selected); };
  }
}

export interface Share {
  index: number;
  name: string;
  symbol: string;
  supply: ethers.BigNumber;
  balance: ethers.BigNumber;
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
  onDialogClose: () => void;
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
  onDialogClose: () => void;
}

export class Vote {
  voteType: number;
  start: number;
  decisionEnd: number;
  decisionRemaining: number;
  decisionTimeProgress: number;
  executionEnd: number;
  executionRemaining: number;
  executionTimeProgress: number;
  stage: number;
  quorumNumerator: number;
  quorumDenominator: number;
  majorityNumerator: number;
  majorityDenominator: number;
  numberOfVotes: string;
  result: number;
  inFavor: ethers.BigNumber;
  against: ethers.BigNumber;
  abstain: ethers.BigNumber;
  noVote: ethers.BigNumber;
  choice: number;
}