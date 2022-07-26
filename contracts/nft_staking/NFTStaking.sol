// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

interface INFTStakingFactory {
    function owner() external view returns (address);
    function getAdminFeePercent() external view returns (uint256);
}

contract NFTStaking is ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    address public factory;

    uint256 public constant PERCENTS_DIVIDER = 1000;
    uint256 public constant YEAR_TIMESTAMP = 31536000;

    /** Staking NFT address */
    address public _stakeNftAddress;
    /** Reward Token address */
    address public _rewardTokenAddress;

    /** NFT price */
    uint256 public _stakeNftPrice;
    /** apr (percent) */
    uint256 public _apr;
    /** apr (percent) */
    uint256 public _rewardPerTimestamp;
    /** creator Address */
    address public _creatorAddress;

    /** Max NFTs that can stake */
    uint256 public _maxStakedNfts;
    /** total staked NFTs*/
    uint256 public _totalStakedNfts;
    /** Max NFTs that a user can stake */
    uint256 public _maxNftsPerUser;
    /** Deposit / Withdraw fee */
    uint256 public _depositFeePerNft;
    uint256 public _withdrawFeePerNft;
    /** Staking start & end time */
    uint256 public _startTime;
    uint256 public _endTime;

    event StartTimeUpdated(uint256 _timestamp);
    event EndTimeUpdated(uint256 _timestamp);
    event RewardTokenUpdated(address newTokenAddress);
    event StakeNftPriceUpdated(uint256 newValue);
    event AprUpdated(uint256 newValue);
    event MaxStakedNftsUpdated(uint256 newValue);
    event MaxNftsPerUserUpdated(uint256 newValue);
    event DepositFeePerNftUpdated(uint256 newValue);
    event WithdrawFeePerNftUpdated(uint256 newValue);

    event Staked(address indexed account, uint256 tokenId, uint256 amount);
    event Withdrawn(address indexed account, uint256 tokenId, uint256 amount);
    event Harvested(address indexed account, uint256 amount);


    constructor() {
        factory = msg.sender;
    }

    function viewUserInfo(address account_) public view returns (
        uint256[] memory stakedNfts,
        uint256[] memory stakedNftAmounts,
        uint256 totalstakedNftCount,
        uint256 rewards,
        uint256 lastRewardTimestamp
    ) {
        stakedNfts = new uint256[](0);
        stakedNftAmounts = new uint256[](0);
        totalstakedNftCount = 0;
        rewards = 0;
        lastRewardTimestamp = block.timestamp;
    }

    function initialize(
        address stakeNftAddress,
        address rewardTokenAddress,
        uint256 stakeNftPrice,
        uint256 apr,
        address creatorAddress,
        uint256 maxStakedNfts,
        uint256 maxNftsPerUser,
        uint256 depositFeePerNft,
        uint256 withdrawFeePerNft,
        uint256 startTime,
        uint256 endTime
    ) external {
        require(msg.sender == factory, "Only for factory");
        _stakeNftAddress = stakeNftAddress;
        _rewardTokenAddress = rewardTokenAddress;
        _stakeNftPrice = stakeNftPrice;
        _apr = apr;
        _creatorAddress = creatorAddress;
        _maxStakedNfts = maxStakedNfts;
        _maxNftsPerUser = maxNftsPerUser;
        _depositFeePerNft = depositFeePerNft;
        _withdrawFeePerNft = withdrawFeePerNft;
        _startTime = startTime;
        _endTime = endTime;
        _rewardPerTimestamp = _apr
            .mul(_stakeNftPrice)
            .div(PERCENTS_DIVIDER)
            .div(YEAR_TIMESTAMP);
    }

    
    /**
     * @dev Update start block timestamp
     * Only factory owner has privilege to call this function
     */
    function updateStartTimestamp(uint256 startTimestamp_)
        external
        onlyFactoryOwner
    {
        require(
            startTimestamp_ <= _endTime,
            "Start block must be before end time"
        );
        require(
            startTimestamp_ > block.timestamp,
            "Start block must be after current block"
        );
        require(_startTime > block.timestamp, "Staking started already");
        _startTime = startTimestamp_;
        emit StartTimeUpdated(startTimestamp_);
    }

    /**
     * @dev Update end block timestamp
     * Only factory owner has privilege to call this function
     */
    function updateEndTimestamp(uint256 endTimestamp_)
        external
        onlyFactoryOwner
    {
        require(
            endTimestamp_ >= _startTime,
            "End block must be after start block"
        );
        require(
            endTimestamp_ > block.timestamp,
            "End block must be after current block"
        );
        _endTime = endTimestamp_;
        emit EndTimeUpdated(endTimestamp_);
    }

    /**
     * @dev Update reward token address
     * Only factory owner has privilege to call this function
     */
    function updateRewardTokenAddress(address rewardTokenAddress_)
        external
        payable
        onlyFactoryOwner
    {
        require(
            _rewardTokenAddress != rewardTokenAddress_,
            "same token address"
        );
        require(_startTime > block.timestamp, "Staking started already");
        uint256 period = _endTime.sub(_startTime);
        uint256 prepareTokenAmount = _stakeNftPrice
            .mul(_maxStakedNfts)
            .mul(_apr)
            .mul(period)
            .div(YEAR_TIMESTAMP)
            .div(PERCENTS_DIVIDER);

        // withdraw previous tokens to creator address
        if (_rewardTokenAddress == address(0x0)) {
            uint256 balance = address(this).balance;
            if (prepareTokenAmount > balance) {
                payable(_creatorAddress).transfer(balance);
            } else {
                payable(_creatorAddress).transfer(prepareTokenAmount);
            }
        } else {
            IERC20 governanceToken = IERC20(_rewardTokenAddress);
            uint256 tokenBalance = governanceToken.balanceOf(address(this));
            if (prepareTokenAmount > tokenBalance) {
                governanceToken.safeTransfer(_creatorAddress, tokenBalance);
            } else {
                governanceToken.safeTransfer(
                    _creatorAddress,
                    prepareTokenAmount
                );
            }
        }

        // deposit previous tokens
        if (rewardTokenAddress_ == address(0x0)) {
            require(msg.value >= prepareTokenAmount, "insufficient balance");
        } else {
            IERC20 governanceToken = IERC20(rewardTokenAddress_);
            require(
                governanceToken.transferFrom(
                    msg.sender,
                    address(this),
                    prepareTokenAmount
                ),
                "insufficient token balance"
            );
        }
        _rewardTokenAddress = rewardTokenAddress_;
        emit RewardTokenUpdated(rewardTokenAddress_);
    }

    /**
     * @dev Update nft price
     * Only factory owner has privilege to call this function
     */
    function updateStakeNftPrice(uint256 stakeNftPrice_)
        external
        payable
        onlyFactoryOwner
    {
        require(_stakeNftPrice != stakeNftPrice_, "same nft price");
        require(_startTime > block.timestamp, "Staking started already");

        uint256 period = _endTime.sub(_startTime);
        uint256 prevTokenAmount = _stakeNftPrice
            .mul(_maxStakedNfts)
            .mul(_apr)
            .mul(period)
            .div(YEAR_TIMESTAMP)
            .div(PERCENTS_DIVIDER);
        uint256 newTokenAmount = stakeNftPrice_
            .mul(_maxStakedNfts)
            .mul(_apr)
            .mul(period)
            .div(YEAR_TIMESTAMP)
            .div(PERCENTS_DIVIDER);

        if (newTokenAmount > prevTokenAmount) {
            // deposit token
            uint256 depositTokenAmount = newTokenAmount.sub(prevTokenAmount);
            if (_rewardTokenAddress == address(0x0)) {
                require(
                    msg.value >= depositTokenAmount,
                    "insufficient balance"
                );
            } else {
                IERC20 governanceToken = IERC20(_rewardTokenAddress);
                require(
                    governanceToken.transferFrom(
                        msg.sender,
                        address(this),
                        depositTokenAmount
                    ),
                    "insufficient token balance"
                );
            }
        } else {
            // withdraw tokens to creator address
            uint256 withdrawTokenAmount = prevTokenAmount.sub(newTokenAmount);
            if (_rewardTokenAddress == address(0x0)) {
                uint256 balance = address(this).balance;
                if (withdrawTokenAmount > balance) {
                    payable(_creatorAddress).transfer(balance);
                } else {
                    payable(_creatorAddress).transfer(withdrawTokenAmount);
                }
            } else {
                IERC20 governanceToken = IERC20(_rewardTokenAddress);
                uint256 tokenBalance = governanceToken.balanceOf(address(this));
                if (withdrawTokenAmount > tokenBalance) {
                    governanceToken.safeTransfer(_creatorAddress, tokenBalance);
                } else {
                    governanceToken.safeTransfer(
                        _creatorAddress,
                        withdrawTokenAmount
                    );
                }
            }
        }

        _stakeNftPrice = stakeNftPrice_;
        _rewardPerTimestamp = _apr
            .mul(stakeNftPrice_)
            .div(PERCENTS_DIVIDER)
            .div(YEAR_TIMESTAMP);
        emit StakeNftPriceUpdated(stakeNftPrice_);
    }

    /**
     * @dev Update apr value
     * Only factory owner has privilege to call this function
     */
    function updateApr(uint256 apr_)
        external
        payable
        onlyFactoryOwner
    {
        require(_apr != apr_, "same apr");
        require(_startTime > block.timestamp, "Staking started already");

        uint256 period = _endTime.sub(_startTime);
        uint256 prevTokenAmount = _stakeNftPrice
            .mul(_maxStakedNfts)
            .mul(_apr)
            .mul(period)
            .div(YEAR_TIMESTAMP)
            .div(PERCENTS_DIVIDER);
        uint256 newTokenAmount = _stakeNftPrice
            .mul(_maxStakedNfts)
            .mul(apr_)
            .mul(period)
            .div(YEAR_TIMESTAMP)
            .div(PERCENTS_DIVIDER);

        if (newTokenAmount > prevTokenAmount) {
            // deposit token
            uint256 depositTokenAmount = newTokenAmount.sub(prevTokenAmount);
            if (_rewardTokenAddress == address(0x0)) {
                require(
                    msg.value >= depositTokenAmount,
                    "insufficient balance"
                );
            } else {
                IERC20 governanceToken = IERC20(_rewardTokenAddress);
                require(
                    governanceToken.transferFrom(
                        msg.sender,
                        address(this),
                        depositTokenAmount
                    ),
                    "insufficient token balance"
                );
            }
        } else {
            // withdraw tokens to creator address
            uint256 withdrawTokenAmount = prevTokenAmount.sub(newTokenAmount);
            if (_rewardTokenAddress == address(0x0)) {
                uint256 balance = address(this).balance;
                if (withdrawTokenAmount > balance) {
                    payable(_creatorAddress).transfer(balance);
                } else {
                    payable(_creatorAddress).transfer(withdrawTokenAmount);
                }
            } else {
                IERC20 governanceToken = IERC20(_rewardTokenAddress);
                uint256 tokenBalance = governanceToken.balanceOf(address(this));
                if (withdrawTokenAmount > tokenBalance) {
                    governanceToken.safeTransfer(_creatorAddress, tokenBalance);
                } else {
                    governanceToken.safeTransfer(
                        _creatorAddress,
                        withdrawTokenAmount
                    );
                }
            }
        }

        _apr = apr_;
        _rewardPerTimestamp = apr_
            .mul(_stakeNftPrice)
            .div(PERCENTS_DIVIDER)
            .div(YEAR_TIMESTAMP);
        emit AprUpdated(apr_);
    }

    /**
     * @dev Update maxStakedNfts value
     * Only factory owner has privilege to call this function
     */
    function updateMaxStakedNfts(uint256 maxStakedNfts_)
        external
        payable
        onlyFactoryOwner
    {
        require(_maxStakedNfts != maxStakedNfts_, "same maxStakedNfts");
        require(_startTime > block.timestamp, "Staking started already");

        uint256 period = _endTime.sub(_startTime);
        uint256 prevTokenAmount = _stakeNftPrice
            .mul(_maxStakedNfts)
            .mul(_apr)
            .mul(period)
            .div(YEAR_TIMESTAMP)
            .div(PERCENTS_DIVIDER);
        uint256 newTokenAmount = _stakeNftPrice
            .mul(maxStakedNfts_)
            .mul(_apr)
            .mul(period)
            .div(YEAR_TIMESTAMP)
            .div(PERCENTS_DIVIDER);

        if (newTokenAmount > prevTokenAmount) {
            // deposit token
            uint256 depositTokenAmount = newTokenAmount.sub(prevTokenAmount);
            if (_rewardTokenAddress == address(0x0)) {
                require(
                    msg.value >= depositTokenAmount,
                    "insufficient balance"
                );
            } else {
                IERC20 governanceToken = IERC20(_rewardTokenAddress);
                require(
                    governanceToken.transferFrom(
                        msg.sender,
                        address(this),
                        depositTokenAmount
                    ),
                    "insufficient token balance"
                );
            }
        } else {
            // withdraw tokens to creator address
            uint256 withdrawTokenAmount = prevTokenAmount.sub(newTokenAmount);
            if (_rewardTokenAddress == address(0x0)) {
                uint256 balance = address(this).balance;
                if (withdrawTokenAmount > balance) {
                    payable(_creatorAddress).transfer(balance);
                } else {
                    payable(_creatorAddress).transfer(withdrawTokenAmount);
                }
            } else {
                IERC20 governanceToken = IERC20(_rewardTokenAddress);
                uint256 tokenBalance = governanceToken.balanceOf(address(this));
                if (withdrawTokenAmount > tokenBalance) {
                    governanceToken.safeTransfer(_creatorAddress, tokenBalance);
                } else {
                    governanceToken.safeTransfer(
                        _creatorAddress,
                        withdrawTokenAmount
                    );
                }
            }
        }

        _maxStakedNfts = maxStakedNfts_;
        _rewardPerTimestamp = _apr
            .mul(maxStakedNfts_)
            .div(PERCENTS_DIVIDER)
            .div(YEAR_TIMESTAMP);
        emit MaxStakedNftsUpdated(maxStakedNfts_);
    }

    /**
     * @dev Update maxNftsPerUser value
     * Only factory owner has privilege to call this function
     */
    function updateMaxNftsPerUser(uint256 maxNftsPerUser_)
        external
        payable
        onlyFactoryOwner
    {           
        _maxNftsPerUser = maxNftsPerUser_;        
        emit MaxNftsPerUserUpdated(maxNftsPerUser_);
    }

    /**
     * @dev Update depositFeePerNft value
     * Only factory owner has privilege to call this function
     */
    function updateDepositFeePerNft(uint256 depositFeePerNft_)
        external
        payable
        onlyFactoryOwner
    {           
        _depositFeePerNft = depositFeePerNft_;        
        emit DepositFeePerNftUpdated(depositFeePerNft_);
    }

    /**
     * @dev Update withdrawFeePerNft value
     * Only factory owner has privilege to call this function
     */
    function updateWithdrawFeePerNft(uint256 withdrawFeePerNft_)
        external
        payable
        onlyFactoryOwner
    {           
        _withdrawFeePerNft = withdrawFeePerNft_;        
        emit WithdrawFeePerNftUpdated(withdrawFeePerNft_);
    }


    /**
     * @dev Safe transfer reward to the receiver
     */
    function safeRewardTransfer(address _to, uint256 _amount)
        internal
        returns (uint256)
    {
        require(_to != address(0), "Invalid null address");
        if (_rewardTokenAddress == address(0x0)) {
            uint256 balance = address(this).balance;
            if (_amount == 0 || balance == 0) {
                return 0;
            }
            if (_amount > balance) {
                _amount = balance;
            }
            payable(_to).transfer(_amount);
            return _amount;
        } else {
            uint256 tokenBalance = IERC20(_rewardTokenAddress).balanceOf(
                address(this)
            );
            if (_amount == 0 || tokenBalance == 0) {
                return 0;
            }
            if (_amount > tokenBalance) {
                _amount = tokenBalance;
            }
            IERC20(_rewardTokenAddress).safeTransfer(_to, _amount);
            return _amount;
        }
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(address token_, uint256 amount_)
        external
        onlyFactoryOwner
    {
        if (token_ == address(0x0)) {
            payable(_creatorAddress).transfer(amount_);
        } else {
            IERC20(token_).safeTransfer(_creatorAddress, amount_);
        }
    }

    
    function withdrawBNB() external onlyFactoryOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "insufficient balance");
        payable(msg.sender).transfer(balance);
    }

    /**
     * @dev Require _msgSender() to be the creator of the token id
     */
    modifier onlyFactoryOwner() {
        address factoryOwner = INFTStakingFactory(factory).owner();
        require(
            factoryOwner == _msgSender(),
            "caller is not the factory owner"
        );
        _;
    }

    /**
     * @dev To receive ETH
     */
    receive() external payable {}
}
