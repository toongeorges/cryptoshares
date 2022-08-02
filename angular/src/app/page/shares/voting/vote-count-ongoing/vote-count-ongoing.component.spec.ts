import { ComponentFixture, TestBed } from '@angular/core/testing';

import { VoteCountOngoingComponent } from './vote-count-ongoing.component';

describe('VoteCountOngoingComponent', () => {
  let component: VoteCountOngoingComponent;
  let fixture: ComponentFixture<VoteCountOngoingComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      declarations: [ VoteCountOngoingComponent ]
    })
    .compileComponents();

    fixture = TestBed.createComponent(VoteCountOngoingComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
