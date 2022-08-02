import { Component, Input, OnInit } from '@angular/core';

@Component({
  selector: 'app-summary',
  templateUrl: './summary.component.html',
  styleUrls: ['./summary.component.scss']
})
export class SummaryComponent implements OnInit {
  public summaryColumns: string[] = [ 'key', 'value' ];

  @Input('summary') public summary: { key: string; value: string; }[] = [];

  constructor() { }

  ngOnInit(): void {
  }

}
