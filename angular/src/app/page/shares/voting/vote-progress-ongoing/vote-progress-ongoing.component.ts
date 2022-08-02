import { Component, Input, OnInit } from '@angular/core';
import { ethers } from 'ethers';
import { EthersService } from 'src/app/services/ethers.service';
import { Share, Vote } from '../../shares.component';

@Component({
  selector: 'app-vote-progress-ongoing',
  templateUrl: './vote-progress-ongoing.component.html',
  styleUrls: ['./vote-progress-ongoing.component.scss']
})
export class VoteProgressOngoingComponent implements OnInit {
  @Input('userAddress') public userAddress: string;
  @Input('share') public share: Share;
  @Input('vote') public vote: Vote;

  @Input('contract') contract: ethers.Contract;
  @Input('pendingRequestId') pendingRequestId: number;
  @Input('onDialogClose') onDialogClose: () => void;
  @Input('formatSeconds') formatSeconds: any;

  constructor(
    public ethersService: EthersService
  ) { }

  ngOnInit(): void {
  }

  withdrawProposal() {
    const contract = this.ethersService.connect(this.contract);
    this.ethersService.showProgressSpinnerUntilExecuted(
      contract['withdrawVote'](),
      this.onDialogClose
    );
  }

  castVote(choice: number) {
    const contract = this.ethersService.connect(this.contract);
    this.ethersService.showProgressSpinnerUntilExecuted(
      contract['vote'](this.pendingRequestId, choice),
      this.onDialogClose
    );
  }

  toDate(epochTime: number) {
    return new Date(epochTime*1000); 
  }
}
