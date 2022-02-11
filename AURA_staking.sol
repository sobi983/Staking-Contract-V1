// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);
}

contract Ownable {
    address private owner;
    bool private _pause = false;

    event OwnerShip_Transferred(
        address indexed previous,
        address indexed current
    );

    constructor() {
        owner = msg.sender;
        emit OwnerShip_Transferred(address(0), owner);
    }

    modifier onlyOwner() {
        if (owner != msg.sender) {
            revert("Only owner can execute this");
        }
        _;
    }

    modifier checkPause() {
        if (_pause == true) {
            revert("Only owner can execute this");
        }
        _;
    }

    function _owner() public view returns (address) {
        return owner;
    }

    function pause() public onlyOwner {
        _pause = true;
    }

    function unPause() public onlyOwner {
        _pause = false;
    }

    function ownership_transfer(address new_owner) public onlyOwner {
        _transferOwnership(new_owner);
    }

    function _transferOwnership(address newOwner) internal {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        owner = newOwner;
        emit OwnerShip_Transferred(owner, newOwner);
    }

    function renounceOwnership() public onlyOwner {
        owner = address(0);
        emit OwnerShip_Transferred(owner, address(0));
    }
}

contract staking is Ownable {
    IERC20 token;
    uint256 totalStakedRecord; //The total of stakes ever been in a pool
    uint256 currentlyStaked; //The current amount of active stakes in a pool
    uint256 public AllocationReward; //Amount of rewards and when this amount is finished the staking would be stopped
    uint256 public minStakingAmount; //The minimum number of staking amount the user can stake for instance a user stake minimum 50 tokens
    uint256 APR; //APR will be static but for the months the APR would be divided accordingly
    uint256 time; //This variable is used to skip timestamps just for the testing purposes; once the contract is finalized by Tokamak it will be removed

    constructor(
        IERC20 _token,
        uint256 _APR,
        uint256 allocation_reward,
        uint256 minS
    ) {
        token = _token;
        APR = _APR;
        AllocationReward = allocation_reward * 10**18; //Decimals 10**18 for the float conversions
        minStakingAmount = 10**18 * minS; //Decimals 10**18 for the float conversions
    }

    struct Stake {
        uint256 totalStaked; //If a user stakes multiple times for multiple time period the the total amount of stake will be saved in this varibale
        uint256[] claim; //When the user stakes n amount the dedicated claim is calculated and then it subtracted from the AllocationReward, in this way we can track the AllocationReward and maintain the functionality of staking; so if nthe pool get out of Allocation reward then the new user will not be able to stake
        uint256[] lastClamiedAmountTime; //It will be highly usable in claiming the reward where the timestamps will be used of the user where we can track when the user have last claimed it reward.
        uint256[] amount; //Number of Amount of stakes stored
        uint256[] since; //The time when the user is staking
        uint256[] expiry; //The time where the user stakes will be expired
    }

    mapping(address => Stake) Stake_Holders;

    function total_staked() public view returns (uint256) {
        return totalStakedRecord;
    }

    function change_APR(uint256 _apr) public onlyOwner {
        //Only owner can change the APR if required
        APR = _apr;
    }

    function change_minStakingAmount(uint256 _msa) public onlyOwner {
        //Only owner can change the minimum amount of Staking requirement
        minStakingAmount = _msa;
    }

    function currently_staked() public view returns (uint256) {
        return currentlyStaked;
    }

    function currentAPR() public view returns (uint256) {
        return APR;
    }

    function stake(uint256 staking_amount, uint256 locking_period)
        public
        checkPause
        returns (bool)
    {
        require(
            token.balanceOf(msg.sender) >= 10**18 * staking_amount &&
                10**18 * staking_amount >= minStakingAmount,
            "The amount is less"
        ); //The stake is checked if it doesn't exceeds the amount of balance it will move for the next execution
        require(locking_period > 0, "Wrong Locking period input");
        _stake(10**18 * staking_amount, locking_period); //Conversion 10***18
        return true;
    }

    function _stake(uint256 stakingAmount, uint256 lockingPeriod) internal {
        address user = msg.sender;
        uint256 currentTime = block.timestamp;
        uint256 guaranteed_reward = calculate_reward(
            stakingAmount,
            lockingPeriod
        ); //The reward will be calculted according to the time period
        require(user != address(0), "InValid address");
        require(
            AllocationReward >= guaranteed_reward,
            "Insufficient allocation reward"
        );
        Stake_Holders[user].amount.push(stakingAmount); //The data of the user will be saved in the array
        Stake_Holders[user].since.push(currentTime);
        Stake_Holders[user].expiry.push(currentTime + lockingPeriod); //The expiry+lockingSeconds will be the timestamp for expiry date
        Stake_Holders[user].claim.push(guaranteed_reward);
        Stake_Holders[user].lastClamiedAmountTime.push(0); //Just to push zero it will be updated once the user claims the reward
        Stake_Holders[user].totalStaked += stakingAmount; //The user Total number of stakes will be stored
        totalStakedRecord += stakingAmount; //Updating
        currentlyStaked += stakingAmount; //Updating
        AllocationReward -= guaranteed_reward; //Here is the main concept where the AllocationReward is reduced once the user has staked into the pool; this will save us from giving extra rewards
        token.transferFrom(msg.sender, address(this), stakingAmount); //The amount from the user account will be transfered to the staking contract to lock for a certain time period
    }

    //Here we are assuming the locking periods for 1,2 and 3 month for testing purposes only once verified we will change it to the desired locking periods
    function calculateAPR(uint256 lock_Period)
        internal
        pure
        returns (uint256 d)
    {
        if (lock_Period == 7776000) {
            //90 days = seconds, 50% APR for 90 days which is 12%
            return 12;
        } else if (lock_Period == 5184000) {
            //60 days.
            return 8;
        } else if (lock_Period == 2592000) {
            //30 days.
            return 4;
        }
    }

    function calculate_reward(uint256 amount, uint256 lockPeriod)
        internal
        pure
        returns (uint256)
    {
        return (amount * calculateAPR(lockPeriod)) / 100; //  Formula:  StakingAmount(TimeStamp for months or more than a year)/100
    }

    function withdraw() public checkPause returns (bool) {
        require(
            Stake_Holders[msg.sender].totalStaked > 0,
            "The user have never staked"
        );
        _withdrawStakes(msg.sender);
        return true;
    }

    //For testing purpose only it will be removed and the contract will be automated once its verified by the tokamak team
    function setTime(uint256 _time) public {
        time = _time;
    }

    function _withdrawStakes(address user) internal {
        uint256 current_blockTime = time; //manually setting up the timestamp so the we could check the fucntionality of the withdraw and claim function
        uint256 withdraw_amount; //This will stored the total amount of withdraw amount of a individual user if the user has staked multiple times and the expiry date is over
        for (uint256 i = 0; i < Stake_Holders[user].expiry.length; i++) {
            if (
                Stake_Holders[user].expiry[i] <= current_blockTime &&
                Stake_Holders[user].amount[i] > 0 //This is a checkpoint if the user has withdrawn already then we will put the amount to zero so for the next time user on the time of withdrw the loop will not iterate of the index which is already withdrawn
            ) {
                withdraw_amount += Stake_Holders[user].amount[i];
                Stake_Holders[user].amount[i] = 0; //Here we are setting up the checkpoint so for the next time the loop will not enter to this condition because it will be withdrwan once it is in here
            }
        }
        require(
            withdraw_amount != 0,
            "Cannot withdraw before a locking period"
        );
        Stake_Holders[user].totalStaked -= withdraw_amount; //If the user has stakes 2 time and it withdraws 1 time and 2nd one is remaining so the withdraw amount will be subtraced from the total amount
        token.transfer(user, withdraw_amount); //token transferred
        currentlyStaked -= withdraw_amount; //update
        if (Stake_Holders[user].totalStaked == 0) {
            //Here is the important check where if the user has withdrawn its all stakes then the user all remaining claims will be rewaded and the data of the user will be deleted
            Claim();
            delete Stake_Holders[user];
        }
    }

    event dis(uint256 indexed); //for testing purpose only

    function Claim() public checkPause {
        uint256 rewardCalculation; //Total reward calculation for different time periods
        uint256 rewardPerSecond; //It will be changedd for every locking period;  Formula: rewardPerSecond = TotalClaimAmount/Expiry-Since
        uint256 current_blockTime = time; //For custom time testing purposes only
        address user = msg.sender;
        require(
            Stake_Holders[user].totalStaked > 0,
            "The user have never staked"
        );
        for (uint256 i = 0; i < Stake_Holders[user].since.length; i++) {
            rewardPerSecond =
                Stake_Holders[user].claim[i] /
                (Stake_Holders[user].expiry[i] - Stake_Holders[user].since[i]);
            if (
                //If the user is clsiming reward before the expiry time
                Stake_Holders[user].expiry[i] > current_blockTime
            ) {
                if (Stake_Holders[user].lastClamiedAmountTime[i] == 0) {
                    //If the user have never claimed before
                    rewardCalculation += (rewardPerSecond *
                        (current_blockTime - Stake_Holders[user].since[i]));

                    Stake_Holders[user].lastClamiedAmountTime[
                            i
                        ] = current_blockTime; //This will be updated so the next time we would know when the user has claimed its reward
                } else if (Stake_Holders[user].lastClamiedAmountTime[i] > 0) {
                    //If the user has ever claimed
                    rewardCalculation += (rewardPerSecond *
                        (current_blockTime -
                            Stake_Holders[user].lastClamiedAmountTime[i])); //Here is the Main concept where the currentTime is subtracted by the last claimed som in this way we will have the exact timeStamp for the the reward will be given

                    Stake_Holders[user].lastClamiedAmountTime[
                            i
                        ] = current_blockTime; //updated
                }
            } else if (Stake_Holders[user].expiry[i] < current_blockTime) {
                //If the user is claiming reward after the expiry period
                if (Stake_Holders[user].lastClamiedAmountTime[i] == 0) {
                    //If the user has never claimed before and the expiry is passed
                    rewardCalculation += Stake_Holders[user].claim[i];
                } else if (Stake_Holders[user].lastClamiedAmountTime[i] > 0) {
                    //This is also one of the main concept where the user will claim after ther expiry but here user has once claimed its reward and for now after the expiry time the user will claim its remaining reward which will be calculated till the expiry
                    rewardCalculation += (rewardPerSecond *
                        (Stake_Holders[user].expiry[i] -
                            Stake_Holders[user].lastClamiedAmountTime[i]));
                }
            }
        }
        require(rewardCalculation > 0, "You can claim amount after 1 minute"); //Here is the check which we have not implemented on line number 244 this will stop user for a certain time period to claim its reward like this: -- for (uint256 i = 0; i < Stake_Holders[user].since.length  && Stake_Holders[user].since[i]>1 minutes; i++)
        emit dis(rewardCalculation); //testing purpose only
        token.transfer(user, rewardCalculation);
    }

    //This will be used for the font end if the user want to withdraw and claim it reward after the expiration time then this function will be called
    function end() public checkPause {
        Claim();
        withdraw();
    }

    function hasStake(address user) public view returns (uint256) {
        user = msg.sender;
        return Stake_Holders[user].totalStaked; //the user total amount staked will be displayed
    }

    //For testing purposes only ....................................................................
    event display(
        uint256 indexed Total_Staked,
        uint256 indexed Claim,
        uint256 LastClaim,
        uint256 indexed AmountPerRound,
        uint256 Since,
        uint256 Expiry
    );

    function stakesTesting(address g) public {
        //  uint256 totalStaked;
        //  uint256 totalClaimAmount;
        //  uint256[] claim;
        //  uint256[] lastClamiedAmountTime;
        //  uint256[] amount;
        //  uint256[] since;
        //  uint256[] expiry;
        for (uint256 i = 0; i < Stake_Holders[g].amount.length; i++) {
            emit display(
                Stake_Holders[g].totalStaked,
                Stake_Holders[g].claim[i],
                Stake_Holders[g].lastClamiedAmountTime[i],
                Stake_Holders[g].amount[i],
                Stake_Holders[g].since[i],
                Stake_Holders[g].expiry[i]
            );
        }
    }
}
