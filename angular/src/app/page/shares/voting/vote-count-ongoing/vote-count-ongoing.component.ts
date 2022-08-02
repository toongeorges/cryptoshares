import { Component, Input, OnInit } from '@angular/core';
import { Vote } from '../../shares.component';

@Component({
  selector: 'app-vote-count-ongoing',
  templateUrl: './vote-count-ongoing.component.html',
  styleUrls: ['./vote-count-ongoing.component.scss']
})
export class VoteCountOngoingComponent implements OnInit {
  @Input('vote') public vote: Vote;

  constructor() { }

  ngOnInit(): void {
  }

}
