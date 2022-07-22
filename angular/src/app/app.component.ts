import { Component, OnInit } from '@angular/core';
import { EthersService } from './services/ethers.service';

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.scss']
})
export class AppComponent implements OnInit {
  constructor(private ethersService: EthersService) {}

  async ngOnInit() {
    await this.ethersService.provider.send("eth_requestAccounts", []);
    console.log("ethers version: " + this.ethersService.version);
    this.ethersService.provider.getSigner().getAddress().then(console.log);
  }
}
