// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "./StructDeclaration.sol";
interface INFTStakingFactory {
    function owner() external view returns (address);
    function getAdminFeePercent() external view returns (uint256);
    function getAdminFeeAddress() external view returns (address);
}

contract NFTStaking is ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public factory;

    uint256 public constant PERCENTS_DIVIDER = 1000;
    uint256 public constant YEAR_TIMESTAMP = 31536000;

    /** Staking NFT address */
    InitializeParam public stakingParams;

    /** apr reward per timestamp */
    uint256 public _rewardPerTimestamp;
    /** total staked NFTs*/
    uint256 public _totalStakedNfts;

    

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

    function getDepositTokenAmount(
        uint256 stakeNftPrice_,
        uint256 maxStakedNfts_,
        uint256 apr_,
        uint256 period_
    ) internal pure returns (uint256) {
        uint256 depositTokenAmount = stakeNftPrice_
            .mul(maxStakedNfts_)
            .mul(apr_)
            .mul(period_)
            .div(YEAR_TIMESTAMP)
            .div(PERCENTS_DIVIDER);
        return depositTokenAmount;
    }

    function initialize(
        InitializeParam memory _param
    ) public initializer {
        factory = msg.sender;
        stakingParams = _param;

        _rewardPerTimestamp = _param.apr
            .mul(_param.stakeNftPrice)
            .div(PERCENTS_DIVIDER)
            .div(YEAR_TIMESTAMP);
    }

    /**
     * @dev Update start block timestamp
     * Only factory owner has privilege to call this function
     */
    function updateStartTimestamp(uint256 startTimestamp_)
        external
        payable
        onlyFactoryOwner
    {
        require(
            startTimestamp_ <= stakingParams.endTime,
            "Start block must be before end time"
        );
        require(
            startTimestamp_ > block.timestamp,
            "Start block must be after current block"
        );
        require(stakingParams.startTime > block.timestamp, "Staking started already");
        require(stakingParams.startTime != startTimestamp_, "same timestamp");

        uint256 prevPeriod = stakingParams.endTime.sub(stakingParams.startTime);
        uint256 newPeriod = stakingParams.endTime.sub(startTimestamp_);
        uint256 prevTokenAmount = getDepositTokenAmount(stakingParams.stakeNftPrice, stakingParams.maxStakedNfts, stakingParams.apr, prevPeriod);
        uint256 newTokenAmount = getDepositTokenAmount(stakingParams.stakeNftPrice, stakingParams.maxStakedNfts, stakingParams.apr, newPeriod);        
        
        if (newTokenAmount > prevTokenAmount) {
            // deposit token
            uint256 depositTokenAmount = newTokenAmount.sub(prevTokenAmount);
            if (stakingParams.rewardTokenAddress == address(0x0)) {
                require(
                    msg.value >= depositTokenAmount,
                    "insufficient balance"
                );
            } else {
                IERC20Upgradeable governanceToken = IERC20Upgradeable(stakingParams.rewardTokenAddress);
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
            if (stakingParams.rewardTokenAddress == address(0x0)) {
                uint256 balance = address(this).balance;
                if (withdrawTokenAmount > balance) {
                    payable(stakingParams.creatorAddress).transfer(balance);
                } else {
                    payable(stakingParams.creatorAddress).transfer(withdrawTokenAmount);
                }
            } else {
                IERC20Upgradeable governanceToken = IERC20Upgradeable(stakingParams.rewardTokenAddress);
                uint256 tokenBalance = governanceToken.balanceOf(address(this));
                if (withdrawTokenAmount > tokenBalance) {
                    governanceToken.safeTransfer(stakingParams.creatorAddress, tokenBalance);
                } else {
                    governanceToken.safeTransfer(
                        stakingParams.creatorAddress,
                        withdrawTokenAmount
                    );
                }
            }
        }

        stakingParams.startTime = startTimestamp_;
        emit StartTimeUpdated(startTimestamp_);
    }

    /**
     * @dev Update end block timestamp
     * Only factory owner has privilege to call this function
     */
    function updateEndTimestamp(uint256 endTimestamp_)
        external
        payable
        onlyFactoryOwner
    {
        require(
            endTimestamp_ >= stakingParams.startTime,
            "End block must be after start block"
        );
        require(
            endTimestamp_ > block.timestamp,
            "End block must be after current block"
        );
        require(endTimestamp_ != stakingParams.endTime, "same timestamp");

        if (endTimestamp_ > stakingParams.endTime) {
            // deposit token
            uint256 period = endTimestamp_.sub(stakingParams.endTime);
            uint256 depositTokenAmount = getDepositTokenAmount(stakingParams.stakeNftPrice, stakingParams.maxStakedNfts, stakingParams.apr, period);
            if (stakingParams.rewardTokenAddress == address(0x0)) {
                require(
                    msg.value >= depositTokenAmount,
                    "insufficient balance"
                );
            } else {
                IERC20Upgradeable governanceToken = IERC20Upgradeable(stakingParams.rewardTokenAddress);
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
            uint256 period = stakingParams.endTime.sub(endTimestamp_);
            uint256 withdrawTokenAmount = getDepositTokenAmount(stakingParams.stakeNftPrice, stakingParams.maxStakedNfts, stakingParams.apr, period);
            
            if (stakingParams.rewardTokenAddress == address(0x0)) {
                uint256 balance = address(this).balance;
                if (withdrawTokenAmount > balance) {
                    payable(stakingParams.creatorAddress).transfer(balance);
                } else {
                    payable(stakingParams.creatorAddress).transfer(withdrawTokenAmount);
                }
            } else {
                IERC20Upgradeable governanceToken = IERC20Upgradeable(stakingParams.rewardTokenAddress);
                uint256 tokenBalance = governanceToken.balanceOf(address(this));
                if (withdrawTokenAmount > tokenBalance) {
                    governanceToken.safeTransfer(stakingParams.creatorAddress, tokenBalance);
                } else {
                    governanceToken.safeTransfer(
                        stakingParams.creatorAddress,
                        withdrawTokenAmount
                    );
                }
            }
        }

        stakingParams.endTime = endTimestamp_;
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
            stakingParams.rewardTokenAddress != rewardTokenAddress_,
            "same token address"
        );
        require(stakingParams.startTime > block.timestamp, "Staking started already");
        uint256 period = stakingParams.endTime.sub(stakingParams.startTime);
        uint256 prepareTokenAmount = getDepositTokenAmount(stakingParams.stakeNftPrice, stakingParams.maxStakedNfts, stakingParams.apr, period);
        

        // withdraw previous tokens to creator address
        if (stakingParams.rewardTokenAddress == address(0x0)) {
            uint256 balance = address(this).balance;
            if (prepareTokenAmount > balance) {
                payable(stakingParams.creatorAddress).transfer(balance);
            } else {
                payable(stakingParams.creatorAddress).transfer(prepareTokenAmount);
            }
        } else {
            IERC20Upgradeable governanceToken = IERC20Upgradeable(stakingParams.rewardTokenAddress);
            uint256 tokenBalance = governanceToken.balanceOf(address(this));
            if (prepareTokenAmount > tokenBalance) {
                governanceToken.safeTransfer(stakingParams.creatorAddress, tokenBalance);
            } else {
                governanceToken.safeTransfer(
                    stakingParams.creatorAddress,
                    prepareTokenAmount
                );
            }
        }

        // deposit previous tokens
        if (rewardTokenAddress_ == address(0x0)) {
            require(msg.value >= prepareTokenAmount, "insufficient balance");
        } else {
            IERC20Upgradeable governanceToken = IERC20Upgradeable(rewardTokenAddress_);
            require(
                governanceToken.transferFrom(
                    msg.sender,
                    address(this),
                    prepareTokenAmount
                ),
                "insufficient token balance"
            );
        }
        stakingParams.rewardTokenAddress = rewardTokenAddress_;
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
        require(stakingParams.stakeNftPrice != stakeNftPrice_, "same nft price");
        require(stakingParams.startTime > block.timestamp, "Staking started already");

        uint256 period = stakingParams.endTime.sub(stakingParams.startTime);
        uint256 prevTokenAmount = getDepositTokenAmount(stakingParams.stakeNftPrice, stakingParams.maxStakedNfts, stakingParams.apr, period);
        uint256 newTokenAmount = getDepositTokenAmount(stakeNftPrice_, stakingParams.maxStakedNfts, stakingParams.apr, period);        

        if (newTokenAmount > prevTokenAmount) {
            // deposit token
            uint256 depositTokenAmount = newTokenAmount.sub(prevTokenAmount);
            if (stakingParams.rewardTokenAddress == address(0x0)) {
                require(
                    msg.value >= depositTokenAmount,
                    "insufficient balance"
                );
            } else {
                IERC20Upgradeable governanceToken = IERC20Upgradeable(stakingParams.rewardTokenAddress);
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
            if (stakingParams.rewardTokenAddress == address(0x0)) {
                uint256 balance = address(this).balance;
                if (withdrawTokenAmount > balance) {
                    payable(stakingParams.creatorAddress).transfer(balance);
                } else {
                    payable(stakingParams.creatorAddress).transfer(withdrawTokenAmount);
                }
            } else {
                IERC20Upgradeable governanceToken = IERC20Upgradeable(stakingParams.rewardTokenAddress);
                uint256 tokenBalance = governanceToken.balanceOf(address(this));
                if (withdrawTokenAmount > tokenBalance) {
                    governanceToken.safeTransfer(stakingParams.creatorAddress, tokenBalance);
                } else {
                    governanceToken.safeTransfer(
                        stakingParams.creatorAddress,
                        withdrawTokenAmount
                    );
                }
            }
        }

        stakingParams.stakeNftPrice = stakeNftPrice_;
        _rewardPerTimestamp = stakingParams.apr
            .mul(stakeNftPrice_)
            .div(PERCENTS_DIVIDER)
            .div(YEAR_TIMESTAMP);
        emit StakeNftPriceUpdated(stakeNftPrice_);
    }

    /**
     * @dev Update apr value
     * Only factory owner has privilege to call this function
     */
    function updateApr(uint256 apr_) external payable onlyFactoryOwner {
        require(stakingParams.apr != apr_, "same apr");
        require(stakingParams.startTime > block.timestamp, "Staking started already");

        uint256 period = stakingParams.endTime.sub(stakingParams.startTime);
        uint256 prevTokenAmount = getDepositTokenAmount(stakingParams.stakeNftPrice, stakingParams.maxStakedNfts, stakingParams.apr, period);
        uint256 newTokenAmount = getDepositTokenAmount(stakingParams.stakeNftPrice, stakingParams.maxStakedNfts, apr_, period);        

        if (newTokenAmount > prevTokenAmount) {
            // deposit token
            uint256 depositTokenAmount = newTokenAmount.sub(prevTokenAmount);
            if (stakingParams.rewardTokenAddress == address(0x0)) {
                require(
                    msg.value >= depositTokenAmount,
                    "insufficient balance"
                );
            } else {
                IERC20Upgradeable governanceToken = IERC20Upgradeable(stakingParams.rewardTokenAddress);
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
            if (stakingParams.rewardTokenAddress == address(0x0)) {
                uint256 balance = address(this).balance;
                if (withdrawTokenAmount > balance) {
                    payable(stakingParams.creatorAddress).transfer(balance);
                } else {
                    payable(stakingParams.creatorAddress).transfer(withdrawTokenAmount);
                }
            } else {
                IERC20Upgradeable governanceToken = IERC20Upgradeable(stakingParams.rewardTokenAddress);
                uint256 tokenBalance = governanceToken.balanceOf(address(this));
                if (withdrawTokenAmount > tokenBalance) {
                    governanceToken.safeTransfer(stakingParams.creatorAddress, tokenBalance);
                } else {
                    governanceToken.safeTransfer(
                        stakingParams.creatorAddress,
                        withdrawTokenAmount
                    );
                }
            }
        }

        stakingParams.apr = apr_;
        _rewardPerTimestamp = apr_
            .mul(stakingParams.stakeNftPrice)
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
        require(stakingParams.maxStakedNfts != maxStakedNfts_, "same maxStakedNfts");
        require(stakingParams.startTime > block.timestamp, "Staking started already");

        uint256 period = stakingParams.endTime.sub(stakingParams.startTime);
        uint256 prevTokenAmount = getDepositTokenAmount(stakingParams.stakeNftPrice, stakingParams.maxStakedNfts, stakingParams.apr, period);
        uint256 newTokenAmount = getDepositTokenAmount(stakingParams.stakeNftPrice, maxStakedNfts_, stakingParams.apr, period);        

        if (newTokenAmount > prevTokenAmount) {
            // deposit token
            uint256 depositTokenAmount = newTokenAmount.sub(prevTokenAmount);
            if (stakingParams.rewardTokenAddress == address(0x0)) {
                require(
                    msg.value >= depositTokenAmount,
                    "insufficient balance"
                );
            } else {
                IERC20Upgradeable governanceToken = IERC20Upgradeable(stakingParams.rewardTokenAddress);
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
            if (stakingParams.rewardTokenAddress == address(0x0)) {
                uint256 balance = address(this).balance;
                if (withdrawTokenAmount > balance) {
                    payable(stakingParams.creatorAddress).transfer(balance);
                } else {
                    payable(stakingParams.creatorAddress).transfer(withdrawTokenAmount);
                }
            } else {
                IERC20Upgradeable governanceToken = IERC20Upgradeable(stakingParams.rewardTokenAddress);
                uint256 tokenBalance = governanceToken.balanceOf(address(this));
                if (withdrawTokenAmount > tokenBalance) {
                    governanceToken.safeTransfer(stakingParams.creatorAddress, tokenBalance);
                } else {
                    governanceToken.safeTransfer(
                        stakingParams.creatorAddress,
                        withdrawTokenAmount
                    );
                }
            }
        }

        stakingParams.maxStakedNfts = maxStakedNfts_;
        _rewardPerTimestamp = stakingParams.apr
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
        stakingParams.maxNftsPerUser = maxNftsPerUser_;
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
        stakingParams.depositFeePerNft = depositFeePerNft_;
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
        stakingParams.withdrawFeePerNft = withdrawFeePerNft_;
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
        if (stakingParams.rewardTokenAddress == address(0x0)) {
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
            uint256 tokenBalance = IERC20Upgradeable(stakingParams.rewardTokenAddress).balanceOf(
                address(this)
            );
            if (_amount == 0 || tokenBalance == 0) {
                return 0;
            }
            if (_amount > tokenBalance) {
                _amount = tokenBalance;
            }
            IERC20Upgradeable(stakingParams.rewardTokenAddress).safeTransfer(_to, _amount);
            return _amount;
        }
    }

    /**
     * @notice Pause / Unpause staking
     */
    function pause(bool flag_) public onlyFactoryOwner {
        if (flag_) {
            _pause();
        } else {
            _unpause();
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
            payable(stakingParams.creatorAddress).transfer(amount_);
        } else {
            IERC20Upgradeable(token_).safeTransfer(stakingParams.creatorAddress, amount_);
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
