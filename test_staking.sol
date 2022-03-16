// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
  function balanceOf(address account) external view returns (uint256);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
  function transfer(address recipient, uint256 amount) external returns (bool);
}

interface UserStats{
  function NumberOfStakesByUser() external view returns(uint256);
  function TotalRemainingStakesOfUser()external view returns(uint256);
  // function TotalRemainingWithdrawalOfUser()external pure returns(uint256);
}

interface RewardStats{
  function RewardsToBePaid() external view returns(uint256);
  function AlreadyPaidRewards() external view returns(uint256);
  function AmountOfRewardsRemainingInPool()external view returns(uint256);
  function IncreaseAllocationReward(uint256 amount)external returns(bool);
  function DecreaseAllocationReward(uint256 amount)external returns(bool);
  function TransferAllocationRewardFromContractToOwner(uint256 amount)external returns(bool);
}


contract Ownable {
     address private owner;
     bool private _pause=false;

     event OwnerShip_Transferred(address indexed previous,address indexed current);

     constructor(){
     owner = msg.sender; 
     emit OwnerShip_Transferred(address(0),owner);
     }

     modifier onlyOwner(){
         if(owner != msg.sender){ revert("Only owner can execute this"); }
         _;
     }

     modifier checkPause(){
       if(_pause == true){ revert("Only owner can execute this"); }
         _;
     }

     function _owner() public view returns(address){
         return owner;
     }
     
     function pause() onlyOwner public{
       _pause=true;
     }

     function unPause() onlyOwner public{
       _pause=false;
     }

     function ownership_transfer(address new_owner) onlyOwner public{
        _transferOwnership(new_owner);
     }

     function _transferOwnership(address newOwner) internal {
         require(newOwner != address(0), "Ownable: new owner is the zero address");
         owner = newOwner;
         emit OwnerShip_Transferred(owner, newOwner);
     }
      function renounceOwnership() onlyOwner public  {
        owner  = address(0);
        emit OwnerShip_Transferred(owner, address(0));
    }
}

contract staking is Ownable, UserStats, RewardStats {

   IERC20 token;
   uint256 totalStakedRecord;
   uint256 currentlyStaked;
   uint256 NumberOfStakesUsers;
   uint256 APR;
   uint256 AllocationReward;
   uint256 Already_Paid_Rewards;
   uint256 Rewards_To_Be_Paid;
   uint256 public minStakingAmount;
   uint256 time; //testing purpose

   constructor(IERC20 _token,uint _APR,uint256 allocation_reward,uint256 minS)
   {
     token=_token;
     APR=_APR;
     AllocationReward=allocation_reward*10**18;
     minStakingAmount=10**18*minS;
   }

   struct Stake
   {
       uint256 totalStaked;
       uint256[] claim;
      //  uint256[] lastClamiedAmountTime;
       uint256[] amount;
       uint256[] since;
       uint256[] expiry;
       uint256[] Locking_Period;
   }

   mapping(address => Stake) Stake_Holders;  
   event StakesOfUser(uint indexed Total_Staked,uint indexed AmountEachTimeStaked,uint Locking_Period,uint Since,uint Expiry);
   event WithdrawOfUser(uint indexed TotalRemainingAmount,uint indexed ClaimedWithdrawn);
   event ChangeAllocationReward(uint256 indexed OldAllocationReward,uint256 indexed CurrentAllocationReward);

   function total_staked()public view returns(uint256)
   {
     return totalStakedRecord;
   }
  
   function change_APR(uint256 _apr) public 
   onlyOwner 
   {
       APR=_apr;
   }
   
   function change_minStakingAmount(uint256 _msa) public 
   onlyOwner 
   {
       minStakingAmount=_msa;
   }

   function currently_staked()public view returns(uint256)
   {
     return currentlyStaked;
   }

   function currentAPR()public view returns(uint)
   {
     return APR;
   }

    function hasStake(address user)public view returns(uint256)
    {
     return Stake_Holders[user].totalStaked;
    }

    function TotalRemainingStakesOfUser()public override view returns(uint256)
    {
      require(Stake_Holders[msg.sender].totalStaked>0,"The user has never staked");
      return Stake_Holders[msg.sender].totalStaked;
    }

    function NumberOfStakesByUser() public override view returns(uint256){
      return NumberOfStakesUsers;
    }

    function RewardsToBePaid() external override view returns(uint256){
       return Rewards_To_Be_Paid;
    }

    function AlreadyPaidRewards() external override view returns(uint256){
       return Already_Paid_Rewards;
    }

    function AmountOfRewardsRemainingInPool() external override view returns(uint256){
       return AllocationReward;
    }

    function IncreaseAllocationReward(uint256 amount)public onlyOwner override returns(bool){
       AllocationReward+=(amount*10**18);
       return true;
    }

    function DecreaseAllocationReward(uint256 amount)external onlyOwner override  returns(bool){
        require(AllocationReward>=amount,"The amount value shouldbe less than AllocationReward");
        AllocationReward-=(amount*10**18);
        return true;
    }

    function TransferAllocationRewardFromContractToOwner(uint256 amount)external onlyOwner override  returns(bool){
         require(AllocationReward>=amount,"The amount value shouldbe less than AllocationReward");
         address user = 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2;
         token.transfer(user,amount*10**18);
         return true;
    }

   function stake(uint256 staking_amount,uint256 locking_period)checkPause public returns(bool)
   {
     require(token.balanceOf(msg.sender) >= 10**18*staking_amount && 10**18*staking_amount>=minStakingAmount,"The amount is less");
     require(locking_period > 0,"Wrong Locking period input");
     _stake(10**18*staking_amount,locking_period);
     NumberOfStakesUsers++;
     return true;
   }
                                             
   function _stake(uint256 stakingAmount,uint lockingPeriod) internal 
   {
       require(lockingPeriod==91.25 days || lockingPeriod==182.5 days || lockingPeriod==365 days || lockingPeriod==1095 days,"The locking period is incorrect");
       address user= msg.sender;
       uint256 currentTime=block.timestamp;
       uint256 guaranteed_reward=calculate_reward(stakingAmount,lockingPeriod);
       require(AllocationReward>=guaranteed_reward,"Insufficient allocation reward");
       Stake_Holders[user].amount.push(stakingAmount);
       Stake_Holders[user].since.push(currentTime);
       Stake_Holders[user].expiry.push(currentTime+lockingPeriod);
       Stake_Holders[user].claim.push(guaranteed_reward);
      //  Stake_Holders[user].lastClamiedAmountTime.push(0);
       Stake_Holders[user].Locking_Period.push(lockingPeriod);
       Stake_Holders[user].totalStaked+= stakingAmount;
       totalStakedRecord+=stakingAmount;
       currentlyStaked+=stakingAmount;
       AllocationReward-=guaranteed_reward;
       Rewards_To_Be_Paid+=guaranteed_reward;
       token.transferFrom(msg.sender,address(this),stakingAmount);
       emit StakesOfUser(Stake_Holders[user].totalStaked,stakingAmount,lockingPeriod,currentTime,currentTime+lockingPeriod);
   }

   function calculate_reward(uint256 amount,uint256 lockPeriod)internal view returns(uint256)
   {    
       
        return ((amount*APR*lockPeriod)/365 days)/100;
   }

   function withdraw(uint256 l_p) checkPause public returns(bool)
   {
       require(Stake_Holders[msg.sender].totalStaked>0,"The user have never staked");
       _withdrawStakes(msg.sender,l_p);
       return true;
   }

//For testing purpose only............
   function setTime(uint _time)public{
     time=_time;
   }
//....................................

   function _withdrawStakes(address user,uint256 lockPeriod) internal
   {
       require(lockPeriod==91.25 days || lockPeriod==182.5 days || lockPeriod==365 days || lockPeriod==1095 days,"The locking period is incorrect");
       uint current_blockTime=time;  //testing purpose
       uint withdraw_amount;
       uint256 claimReward;
      for(uint i=0;i<Stake_Holders[user].Locking_Period.length;i++)
      {
         if(Stake_Holders[user].Locking_Period[i]==lockPeriod && Stake_Holders[user].expiry[i]<=current_blockTime && Stake_Holders[user].since[i]>0 )
         {
          withdraw_amount+=Stake_Holders[user].amount[i];
          Stake_Holders[user].since[i]=0;
          NumberOfStakesUsers--;
         }
      }
       require(withdraw_amount!=0,"Cannot withdraw before a locking period");
       Stake_Holders[user].totalStaked -= withdraw_amount;
       currentlyStaked -=withdraw_amount;
       claimReward=ClaimOnlyWhenWithdraw(user,lockPeriod);
       withdraw_amount+=claimReward;
       Rewards_To_Be_Paid-=claimReward;
       Already_Paid_Rewards+=claimReward;
       require(token.balanceOf(address(this))>=withdraw_amount,"The reward allocation is insufficient");
       token.transfer(user,withdraw_amount);
       if(Stake_Holders[user].totalStaked==0){
        //  Claim(lockPeriod);
         delete Stake_Holders[user];
       }
        emit WithdrawOfUser(Stake_Holders[user].totalStaked,withdraw_amount);
   }

   function ClaimOnlyWhenWithdraw(address user,uint256 LockPeriod)internal  returns(uint256){
      uint256 current_blockTime=time;
      uint256 rewardCalculation;
     for(uint i=0;i<Stake_Holders[user].Locking_Period.length;i++){
       if(Stake_Holders[user].Locking_Period[i]==LockPeriod && Stake_Holders[user].expiry[i] <= current_blockTime && Stake_Holders[user].claim[i]>0)
       {
         rewardCalculation+= Stake_Holders[user].claim[i];
         Stake_Holders[user].claim[i]=0;
       }
     }
     return rewardCalculation;
   }

  // event dis(uint256 indexed);  //for testing purpose only
  //  function Claim(uint256 lockPeriod) checkPause public { 
  //      uint256 rewardCalculation;
  //      uint256 rewardPerSecond;
  //      uint256 current_blockTime=time;
  //      address user=msg.sender;
  //      require(Stake_Holders[user].totalStaked>0,"The user have never staked");
  //      for(uint i=0;i<Stake_Holders[user].since.length;i++){
  //        rewardPerSecond=Stake_Holders[user].claim[i]/(Stake_Holders[user].expiry[i]-Stake_Holders[user].since[i]);
  //        if(Stake_Holders[user].expiry[i]>current_blockTime && Stake_Holders[user].Locking_Period[i]==lockPeriod)
  //        {    
  //           if(Stake_Holders[user].lastClamiedAmountTime[i]==0){
  //             rewardCalculation+=(rewardPerSecond*(current_blockTime-Stake_Holders[user].since[i])); 
          
  //             Stake_Holders[user].lastClamiedAmountTime[i]=current_blockTime;
  //            }
  //           else if(Stake_Holders[user].lastClamiedAmountTime[i]>0){
  //             rewardCalculation+=(rewardPerSecond*(current_blockTime-Stake_Holders[user].lastClamiedAmountTime[i])); 
        
  //             Stake_Holders[user].lastClamiedAmountTime[i]=current_blockTime;
  //            }
  //        }
  //        else if(Stake_Holders[user].expiry[i]<current_blockTime && Stake_Holders[user].Locking_Period[i]==lockPeriod){
  //            if(Stake_Holders[user].lastClamiedAmountTime[i]==0){
  //             rewardCalculation+=Stake_Holders[user].claim[i];
  //             Stake_Holders[user].claim[i]-=rewardCalculation;
       
  //            }
  //           else if(Stake_Holders[user].lastClamiedAmountTime[i]>0){
  //             rewardCalculation+=(rewardPerSecond*(Stake_Holders[user].expiry[i]-Stake_Holders[user].lastClamiedAmountTime[i])); 
  //             Stake_Holders[user].claim[i]-=rewardCalculation;
             
  //            }
  //        }
  //      }
  //      require(rewardCalculation>0,"You can claim amount after 1 minute");
  //      emit dis(rewardCalculation);  //testing purpose only
  //      token.transfer(user,rewardCalculation);
  //  }

  //  function end()checkPause public{
  //    Claim();
  //    withdraw();
  //  }





//For testing purposes only ...................................
   event display(uint indexed Total_Staked,uint indexed Claim,uint indexed AmountEachTimeStaked,uint Locking_Period,uint Since,uint Expiry);
   function stakesTesting(address g)public{
      //  uint256 totalStaked;
      //  uint256 totalClaimAmount;
      //  uint256[] claim;
      //  uint256[] lastClamiedAmountTime;
      //  uint256[] amount;
      //  uint256[] since;
      //  uint256[] expiry;
     for(uint i=0;i<Stake_Holders[g].amount.length;i++){
        emit display(Stake_Holders[g].totalStaked,Stake_Holders[g].claim[i],Stake_Holders[g].amount[i],Stake_Holders[g].Locking_Period[i],Stake_Holders[g].since[i],Stake_Holders[g].expiry[i]);
     }
   }
}
