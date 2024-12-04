// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Initializable.sol";
import "./IERC20.sol";

contract TokenStaking is Ownable, ReentrancyGuard, Initializable {

    struct User {
        uint256 stakeAmmont;
        uint256 rewardAmount;
        uint256 lastStakeTime;
        uint256 lastRewardCalculationTime;
        uint256 rewardClaimSofar;
    }
    
    uint256 _minimumStakingAmount;
    uint256 _maxStakeTokenLimit;
    uint256 _stakeEndDate;
    uint256 _stakeStartDate;
    uint256 _totalStakedTokens;
    uint256 _totalUsers;
    uint256 _stakeDays;

    uint256 _earlyUnstakeFeePercentage;
    bool _isStakingPaused;
    address private _tokenAddress;

    uint256 _apyRate;

    uint256 public constant PERCENTAGE_DENOMINATOR = 10000;
    uint256 public constant APY_RATE_CHANGE_THRESHOLD = 10;

    mapping(address => User) private_users;

    event Stake(address indexed user, uint256 amount);
    event UnStake(address indexed user, uint256 amount);
    event EarlyUnstakeFee(address indexed user, uint256 amount);
    event ClaimReward(address indexed user, uint256 amount);

    modifier whenTreasuryHasBalance(uint256 amount) {
        require(
            IERC20(_tokenAddress).balanceOf(address(this)) >= amount,
            "TokenStaking: insufficient funds in the treasury"
        );
        _;
    }

    function initialize( 
        address owner_,
        address tokenAddress_,
        uint256 apyRate_,
        uint256 minimumStakingAmount_,
        uint256 maxStakeTokenLimit_,
        uint256 stakeStartDate_,
        uint256 stakeStartDate_,
        uint256 stakeEndDate_,
        uint256 stakeDays_,
        uint256 earlyUnstakeFeePercentage_
    ) public virtual initializer {
        _TokenStaking_init_unchained(
            owner_,
            tokenAddress_,
            apyRate_,
            minimumStakingAmount_,
            maxStakeTokenLimit_,
            stakeStartDate_,
            stakeEndDate_,
            stakeDays_,
            earlyUnstakeFeePercentage_
        );
    }

    function _TokenStaking_init_unchained(
        address owner_,
        address tokenAddress_,
        uint256 apyRate_,
        uint256 minimumStakingAmount_,
        uint256 maxStakeTokenLimit_,
        uint256 stakeStartDate_,
        uint256 stakeStartDate_,
        uint256 stakeEndDate_,
        uint256 stakeDays_,
        uint256 earlyUnstakeFeePercentage_
    ) internal onlyInitializing{
        require(_apyRate <= 10000, "TokenStaking: apy rate should be less than 10000");
        require(stakeDays_ > 0, "TokenStaking: stake days must be greater than zero");
        require(tokenAddress_ != address(0), "TokenStaking: token address cannot be zero");
        require(stakeStartDate_ < stakeEndDate_, "TokenStaking: start date must be less than end date");
        _transferOwnership(owner_);
        _tokenAddress = tokenAddress_;
        _apyRate = apyRate_;
        _minimumStakingAmount = minimumStakingAmount_;
        _maxStakeTokenLimit = maxStakeTokenLimit_;
        _stakeStartDate = stakeStartDate_;
        _stakeEndDate = stakeEndDate_;
        _stakeDays = stakeDays_ * 1 days;
        _earlyUnstakeFeePercentage = earlyUnstakeFeePercentage_;
    }

    function getMinimumStakingAmount() external view returns (uint256) {
        return _minimumStakingAmount;
    }

    function getMaxStakingTokenLimit() external view returns (uint256) {
        return _maxStakeTokenLimit;
    }

    function getStakeStartDate() external view returns (uint256) {
        return _stakeStartDate;
    }

    function getStakeEndDate() external view returns (uint256) {
        return _stakeEndDate;
    }

    function getTotalStakedTokens() external view returns (uint256) {
        return _totalStakedTokens;
    }

    function getTotalUsers() external view returns (uint256) {
        return _totalUsers;
    }

    function getStakeDays() external view returns (uint256) {
        return _stakeDays;
    }

    function getEarlyUnstakeFeePercentage() external view returns (uint256) {
        return _earlyUnstakeFeePercentage;
    }

    function getStakingStatus() external view returns (uint256) {
        return _isStakingPaused;
    }

    function getApy() external view returns (uint256) {
        return _apyRate;
    }
    function getUserEstimatedRewards() external view returns (uint256) {
        (uint256 amount, ) = _getUserEstimatedRewards(msg.sender);
        return _users[msg.sender].rewardAmount + amount;
    }

    function getWithdrawableAmount() external view returns(uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this)) - _totalStakedTokens;
    }

    function getUser(address userAddress) external view returns (User memory) {
        return _users[userAddress];
    }

    function isStakeHolder( address _user) external view returns (bool) {
        return _users[_user].stakeAmount != 0;
    }

    function updateMinimumStakingAmount(uint256 newAmount) external onlyOwner {
        _minimumStakingAmount = newAmount;
    }

    function updateMaximumStakingAmount(uint256 newAmount) external onlyOwner{
        _maxStakeTokenLimit = newAmount;
    }

    function updateStakingEndDate(uint256 newDate) external onlyOwner {
        _stakeEndDate = newDate;
    }

    function updateEarlyUnstakingFeePercentage(uint256 newPercentage) external onlyOwner {
        _earlyUnstakeFeePercentage = newPercentage;
    }

    function stakeForUser(uint256 amount, address user) external onlyOwner nonReentrant {
       _stakeToken(amount, user); 
    }

    function toggleStakingStatus() external onlyOwner {
        _isStakingPaused = !_isStakingPaused;
    }

    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        require(this.getWithdrawableAmount() >= amount, "TokenStaking: not enough withdrawable tokens");
        IERC20(_tokenAddress).transfer(msg.sender, amount);
    }
     // user functions

    function stake(uint256 _amount) external nonReentrant {
        _stakeTokens(_amount, msg.sender);
    }

    function _stakeTokens(uint256 _amount, address _user) private {
        require(!_isStakingPaused, "TokenStaking: staking is paused");

        uint256 currentTime = getCurrentTime();
        require(currentTime > _stakeStartDate, "TokenStaking: staking not started yet");
        require(currentTime < _stakeEndDate, "TokenStaking: staking ended");
        require(_totalStakedTokens + _amount <= _maxStakeTokenLimit, "TokenStaking: max staking token limit required");

        require(_amount > 0, "TokenStaking: stake amount must be non-zero");
        require(_amount >= _minimumStakingAmount, "TokenStaking: stake amount must be greater than minimum amount allowed");

        if (_users[user_].stakeAmount != 0) {
            _calculateRewards(user_);
        } else {
            _users[user_].lastRewardCalculationTime = currentTime;
            _totalUsers += 1;
        }

        _users[user_].stakeAmount += _amount;
        _users[user_].lastStakeTime = currentTime;

        _totalStakedTokens += _amount;

        require(
            IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount),
            "TokenStaking: failed to transfer tokens"
        );
        emit Stake(user_, _amount);
    }

    function unstake(uint256 _amount) external nonReentrant whenTreasuryHasBalance(_amount) {
        address user = msg.sender;

        require(_amount != 0, "TokenStaking: amount should be non-zero");
        require(this.isStakeHolder(user), "TokenStaking: not a stakeholder");
        require(_users[user].stakeAmount >= _amount, "TokenStaking: not enough stake to unstake");

        _calculateRewards(user);

        uint256 feeEarlyUnstake;

        if (getCurrentTime() <= _users[user].lastStakeTime + _stakeDays) {
            feeEarlyUnstake = ((_amount * _earlyUnstakeFeePercentage)/ PERCENTAGE_DENOMINATOR);
            emit EarlyUnstakeFee(user, feeEarlyUnstake);
        }

        unit256 amountToUnstake = _amount - feeEarlyUnstake;

        _users[user].stakeAmount -= _amount;
        _totalStakedTokens -= _amount;
        
        if (_user[user].stakeAmount == 0) {
            _totalUsers -= 1;
        }
        
        require(IERC20(_tokenAddress).transfer(user, amountToUnstake), "TokenStaking: failed to transfer");
        emit UnStake(user, _amount);
    }
    
    function claimReward() external nonReentrant whenTreasuryHasBalance(_users[msg.sender].rewardAmount) {
        _calculateRewards(msg.sender);
        uint256 rewardAmount = _users[msg.sender].rewardAmount;

        require(rewardAmount > 0, "TokenStaking: no reward to Claim");

        require(IERC20(_tokenAddress).transfer(msg.sender, rewardAmount), "TokenStaking: failed to transfer");

        _users[msg.sender].rewardAmount = 0;
        _users[msg.sender].rewardsClaimedSoFar += rewardAmount;

        emit ClaimReward(msg.sender, rewardAmount);
    }

    function _calculateRewards(address _user) private {
        (uint256 userReward, uint256 currentTime) = _getUserEstimatedRewards(_user);
        _users[_user].rewardAmount += userReward;
        _users[_user].lastRewardCalculationsTime = currentTime;
    }

    function _getUserEstimatedRewards(address _user) private view returns (uint256, uint256) {
        uint256 userReward;
        uint256 userTimestamp = _users[_user].lastRewardCalculationTime;

        uint256 currentTime = getCurrentTime();
        if (currentTime > _users[_user].lastStakeTime + _stakeDays) {
            currentTime = _users[_user].lastStakeTime + +_stakeDays;
        }

        uint256 _totalStakedTime = currentTime - userTimestamp;
        userReward += ((totalStakedTime * _users[_user].stakeAmount * _apyRate)/ 365 days) / PERCENTAGE_DENOMINATOR;

        return (userReward, currentTime);
    }


    function getCurrentTime() internal view virtual returns(uint256) {
        return block.timestamp;
    }



}