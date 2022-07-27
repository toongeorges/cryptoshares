import { AfterViewInit, Component, OnInit, ViewChild } from '@angular/core';
import { MatDialog } from '@angular/material/dialog';
import { MatPaginator } from '@angular/material/paginator';
import { MatSort } from '@angular/material/sort';
import { MatTableDataSource } from '@angular/material/table';
import { ethers } from "ethers";
import { EthersService } from 'src/app/services/ethers.service';
import * as shareData from '../../../../../solidity/artifacts/contracts/Share.sol/Share.json';

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
  
        let name = await contract['name']();
        let symbol = await contract['symbol']();
  
        this.shares.push({
          index: i,
          name: name,
          symbol: symbol
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
}

export interface Share {
  index: number;
  name: string;
  symbol: string;
}
