// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
/// @title Simple Staking
/// @author jawad-unmarshal
/// @notice Simple Staking and rewards program for any ERC20 compatible token

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Utils/ERC20Utils.sol";

contract BasicStakingContract {
    struct UserStake {
        uint stakeAmount;
        uint stakeStartBlockNumber;
        address staker;
        uint claimed;
        bool stakeStatus;
    }

    IERC20 public stakingToken;
    address public contractOwner;
    uint public minimumStake;
    uint public payoutGap;
    mapping(address => UserStake) public stakeMap;
    mapping(address => uint) public withdrawPool;

    /// @notice Emitted at the end of a successful stake
    /// @dev Emitted anytime a stake is started
    /// @param staker The address of the user staking
    /// @param stakedAmount The total amount locked into the contract by the user
    event Stake(
        address indexed staker,
        uint256 stakedAmount
    );

    /// @notice Emitted whenever the user's claims are sent to the withdraw pool
    /// @dev Must be emitted after a successful claim including after an Unstake
    /// @param staker The address of the user staking
    /// @param claimedAmount The amount claimed and sent to the WithdrawPool
    event Claim(
        address indexed staker,
        uint256 claimedAmount
    );

    /// @notice Emitted after a successful unstake
    /// @dev Emitted when a user's StakeStatus is updated to False
    /// @param staker The address of the user staking
    /// @param stakedAmount The total amount locked into the contract by the user
    event Unstake(
        address indexed staker,
        uint256 stakedAmount
    );

    modifier onlyOwner() {
        require(
            msg.sender == contractOwner,
            "Must be contract owner to make call"
        );
        _;
    }

    modifier noActiveStake() {
        require(
            !_hasActiveStake(msg.sender),
            "Must not have active stake"
        );
        _;
    }
    modifier activeStake() {
        require(
            _hasActiveStake(msg.sender),
            "Must have an active stake"
        );
        _;
    }

    modifier hasMoneyInWithdrawPool() {
        require(
            withdrawPool[msg.sender] > 0,
            "Need to have non zero sum of money in withdrawal pool"
        );
        _;
    }

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @param _stakingToken the address of the token contract
    /// @param _minimumStake The minimum amount of tokens that need to be staked
    /// @param _payoutGap the number of blocks a stake must be present to earn 1 token from _stakingToken
    constructor(IERC20 _stakingToken, uint _minimumStake, uint _payoutGap)  {
        stakingToken = _stakingToken;
        minimumStake = _minimumStake;
        payoutGap = _payoutGap;
        contractOwner = msg.sender;
    }

    /// @notice Updates the Minimum Stake Amount
    /// @dev Only accessible to the contract's owner
    /// @param _stakeAmount The updated stake amount to qualify as minimum
    function setMinimumStake(uint256 _stakeAmount) external onlyOwner {
        minimumStake = _stakeAmount;
    }

    /// @notice Start a stake by depositing the required minimum tokens into the contract
    /// @dev modifier noActiveStake present to make sure user doesn't already have a stale present
    /// @param _stakeAmount the amount of tokens the user is willing to stake
    function stake(uint256 _stakeAmount) external payable noActiveStake {
        require(_stakeAmount >= minimumStake, "Staked amount too low");
        Erc20Utils.addTokensToContract(stakingToken, payable(msg.sender), _stakeAmount);
        UserStake memory _stake = UserStake(_stakeAmount, block.number, msg.sender, 0, true);
        stakeMap[msg.sender] = _stake;
        emit Stake(msg.sender, _stakeAmount);
    }

    /// @notice Claim Tokens earned as reward for staking
    /// @dev The function transfers the claimable tokens to the withdrawPool. withdrawFromPool will initiate the transfer
    function claim() external activeStake {
        uint claimableTokens = getClaimableToken(msg.sender);
        require(claimableTokens > 0, "0 claimable tokens present");
        UserStake storage _stake = stakeMap[msg.sender];
        _stake.claimed += claimableTokens;
        withdrawPool[msg.sender] += claimableTokens;
        emit Claim(msg.sender, claimableTokens);
    }

    /// @notice Unstake your tokens and exit the stake
    /// @dev The contract claims tokens for the users and adds the available claim to the withdrawPool in addition to the staked amount
    function unstake() external activeStake {
        UserStake storage _stake = stakeMap[msg.sender];
        uint claimableTokens = getClaimableToken(msg.sender);
        if (claimableTokens > 0) {
            _stake.claimed += claimableTokens;
            withdrawPool[msg.sender] += claimableTokens;
            emit Claim(msg.sender, claimableTokens);
        }
        _stake.stakeStatus = false;
        _stake.stakeStartBlockNumber = 0;
        _stake.claimed = 0;
        uint stakeAmt = _stake.stakeAmount;
        _stake.stakeAmount = 0;
        withdrawPool[msg.sender] += stakeAmt;
        emit Unstake(msg.sender, stakeAmt);
    }

    /// @notice This call allows anyone owed money by the contract to collect it by initiating a transfer to their account.
    /// @dev This call transfers all amount available in the withdrawPool for te caller to their account and resets it.
    function withdrawFromPool() external payable hasMoneyInWithdrawPool {
        address payable callerAddress = payable(msg.sender);
        uint256 amt = withdrawPool[msg.sender];
        withdrawPool[msg.sender] = 0;
        Erc20Utils.moveTokensFromContract(stakingToken, callerAddress, amt);
    }

    /// @notice Show the number of tokens available to claim
    /// @param _stakerAddress the address of the staker
    /// @return claimableTokens the number of tokens that can be claimed
    function getClaimableToken(address _stakerAddress) public view returns (uint claimableTokens){
        uint earnedTokens = getEarnedTokens(_stakerAddress);
        if (earnedTokens == 0) {
            return 0;
        }
        claimableTokens = SafeMath.sub(earnedTokens, stakeMap[_stakerAddress].claimed);
        return claimableTokens;
    }

    /// @notice Get the total amount of tokens earned upto this point. This includes claimed tokens as well.
    /// @param _stakerAddress The address of the staker involved
    /// @return earnedTokens The total amount of tokens earned
    function getEarnedTokens(address _stakerAddress) public view returns (uint earnedTokens) {
        UserStake memory staker = stakeMap[_stakerAddress];
        if (!stakeMap[_stakerAddress].stakeStatus) {
            return 0;
        }
        uint blockDiff = SafeMath.sub(block.number, staker.stakeStartBlockNumber);
        if (blockDiff <= payoutGap) {
            return 0;
        }
        earnedTokens = SafeMath.div(blockDiff, payoutGap);
        return earnedTokens;
    }

    function _hasActiveStake(address _userAddress) internal view returns (bool) {
        return (stakeMap[_userAddress].stakeStatus);
    }


}
