import { Component, OnInit } from '@angular/core';
import { EthersService } from './services/ethers.service';

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.scss']
})
export class AppComponent implements OnInit {
  links = [
    {
      'label': 'Exchange',
      'route': 'exchange'
    },
    {
      'label': 'Shares',
      'route': 'shares'
    },
    {
      'label': 'SeedTokens',
      'route': 'seedtokens'
    }
  ];
  activeLink = this.links[0];

  constructor(private ethersService: EthersService) {}

  async ngOnInit() {
    await this.ethersService.provider.send("eth_requestAccounts", []);
    console.log("ethers version: " + this.ethersService.version);
  }
}
