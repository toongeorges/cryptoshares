import { AfterViewInit, Component, OnInit, ViewChild } from '@angular/core';
import { MatPaginator } from '@angular/material/paginator';
import { MatSort } from '@angular/material/sort';
import { MatTableDataSource } from '@angular/material/table';
import { ethers } from "ethers";
import { EthersService } from 'src/app/services/ethers.service';
import * as seedTokenData from '../../../../../solidity/artifacts/contracts/SeedToken.sol/SeedToken.json';

@Component({
  selector: 'app-seedtokens',
  templateUrl: './seedtokens.component.html',
  styleUrls: ['./seedtokens.component.scss']
})
export class SeedtokensComponent implements OnInit, AfterViewInit {
  private seedTokens: SeedToken[] = [];

  public displayedColumns: string[] = ['name', 'symbol', 'amount'];
  public dataSource = new MatTableDataSource(this.seedTokens);

  private contracts: ethers.Contract[] = [];

  @ViewChild(MatPaginator) paginator: MatPaginator;
  @ViewChild(MatSort) sort: MatSort;

  constructor(private ethersService: EthersService) { }

  async ngOnInit() {
    let numberOfTokens = await this.ethersService.seedTokenFactory['getNumberOfTokens']();

    for (let i = 0; i < numberOfTokens; i++) {
      let seedTokenAddress = await this.ethersService.seedTokenFactory['tokens'](i);

      let contract = new ethers.Contract(
        seedTokenAddress,
        (seedTokenData as any).default.abi,
        this.ethersService.provider
      );
      this.contracts.push(contract);

      let name = await contract['name']();
      let symbol = await contract['symbol']();
      let address = await this.ethersService.provider.getSigner().getAddress();
      let decimals = await contract['decimals']();
      let amount = await contract['balanceOf'](address)
      amount = ethers.BigNumber.from(amount).div(ethers.BigNumber.from('10').pow(decimals));

      this.seedTokens.push({
        name: name,
        symbol: symbol,
        amount: amount
      });

      this.dataSource = new MatTableDataSource(this.seedTokens);
      this.dataSource.paginator = this.paginator;
      this.dataSource.sort = this.sort;
    }
  }

  ngAfterViewInit() {
    this.dataSource.paginator = this.paginator;
    this.dataSource.sort = this.sort;
  }
}

export interface SeedToken {
  name: string;
  symbol: string;
  amount: string;
}
