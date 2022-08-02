import { AfterViewInit, Component, Input, OnInit } from '@angular/core';
import { ethers } from 'ethers';
import { EthersService } from 'src/app/services/ethers.service';
import { Vote } from '../../shares.component';

@Component({
  selector: 'app-vote-details-change-decision-parameters',
  templateUrl: './vote-details-change-decision-parameters.component.html',
  styleUrls: ['./vote-details-change-decision-parameters.component.scss']
})
export class VoteDetailsChangeDecisionParametersComponent implements OnInit, AfterViewInit {
  @Input('vote') public vote: Vote;

  @Input('contract') contract: ethers.Contract;
  @Input('pendingRequestId') pendingRequestId: number;
  @Input('formatSeconds') formatSeconds: any;

  public proposal: ProposedDecisionParameters;

  constructor(
    public ethersService: EthersService
  ) { }

  ngOnInit(): void {
  }

  ngAfterViewInit(): void {
    this.contract['getProposedDecisionParameters'](this.pendingRequestId).then((proposal: any[]) => {
      this.proposal = {
        type: proposal[0],
        subType: 0,
        decisionTime: proposal[1],
        executionTime: proposal[2],
        quorumNumerator: proposal[3],
        quorumDenominator: proposal[4],
        majorityNumerator: proposal[5],
        majorityDenominator: proposal[6]
      }  

      if (this.proposal.type >= this.ethersService.shareActions.length) {
        this.proposal.subType = this.proposal.type - (this.ethersService.shareActions.length - 1);
      }
    });
  }
}

export class ProposedDecisionParameters {
  type: number;
  subType: number;
  decisionTime: number;
  executionTime: number;
  quorumNumerator: number;
  quorumDenominator: number;
  majorityNumerator: number;
  majorityDenominator: number;
}