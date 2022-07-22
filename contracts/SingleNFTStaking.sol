// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";


contract NftStaking is ReentrancyGuard, Pausable, IERC721Receiver {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    uint256 constant public PERCENTS_DIVIDER = 1000;

    /** Staking NFT address */
    address public _stakeNftAddress;
    /** Reward Token address */
    address public _rewardTokenAddress;
    /** Fee address */
    address payable public _feeAddress;
    /** Reward per block */
    uint256 public _rewardPerBlock = 1 ether;
    /** Max NFTs that a user can stake */
    uint256 public _maxNftsPerUser = 1;
    /** Deposit / Withdraw fee */
    uint256 public _depositFeePerNft = 0.025 ether;
    uint256 public _withdrawFeePerNft = 0.025 ether;
    /** Staking start & end block */
    uint256 public _startBlock;
    uint256 public _endBlock;    

    struct UserInfo {
        EnumerableSet.UintSet stakedNfts;
        uint256 rewards;
        uint256 lastRewardBlock;
    }

    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) private _userInfo;

    event RewardPerBlockUpdated(uint256 oldValue, uint256 newValue);
    event Staked(address indexed account, uint256 tokenId);
    event Withdrawn(address indexed account, uint256 tokenId);
    event Harvested(address indexed account, uint256 amount);

    constructor(
        address stakeNftAddress_,
        address rewardTokenAddress_,
        address payable feeAddress_,
        uint256 startBlock_,
        uint256 endBlock_,
        uint256 rewardPerBlock_
    ) {
        IERC20(rewardTokenAddress_).balanceOf(address(this));
        IERC721(stakeNftAddress_).balanceOf(address(this));        
        require(rewardPerBlock_ > 0, "Invalid reward per block");
        require(
            startBlock_ <= endBlock_,
            "Start block must be before end block"
        );
        require(
            startBlock_ > block.number,
            "Start block must be after current block"
        );

        _stakeNftAddress = stakeNftAddress_;
        _rewardTokenAddress = rewardTokenAddress_;
        _feeAddress = feeAddress_;
        _rewardPerBlock = rewardPerBlock_;
        _startBlock = startBlock_;
        _endBlock = endBlock_;
    }

    function viewUserInfo(address account_)
        external
        view
        returns (
            uint256[] memory stakedNfts,
            uint256 rewards,
            uint256 lastRewardBlock
        )
    {
        UserInfo storage user = _userInfo[account_];
        rewards = user.rewards;
        lastRewardBlock = user.lastRewardBlock;
        uint256 countNfts = user.stakedNfts.length();
        if (countNfts == 0) {
            // Return an empty array
            stakedNfts = new uint256[](0);
        } else {
            stakedNfts = new uint256[](countNfts);
            uint256 index;
            for (index = 0; index < countNfts; index++) {
                stakedNfts[index] = tokenOfOwnerByIndex(account_, index);
            }
        }
    }

    function tokenOfOwnerByIndex(address account_, uint256 index_)
        public
        view
        returns (uint256)
    {
        UserInfo storage user = _userInfo[account_];
        return user.stakedNfts.at(index_);
    }

    function userStakedNFTCount(address account_)
        public
        view
        returns (uint256)
    {
        UserInfo storage user = _userInfo[account_];
        return user.stakedNfts.length();
    }

    /**
     * @dev Update fee address
     * Only owner has privilege to call this function
     */
    function updateFeeAddress(address payable feeAddress_) external onlyOwner {
        _feeAddress = feeAddress_;
    }

    /**
     * @dev Update deposit fee per nft
     * Only owner has privilege to call this function
     */
    function updateDepositFeePerNft(uint256 depositFee_) external onlyOwner {
        _depositFeePerNft = depositFee_;
    }

    /**
     * @dev Update withdraw fee per nft
     * Only owner has privilege to call this function
     */
    function updateWithdrawFeePerNft(uint256 withdrawFee_) external onlyOwner {
        _withdrawFeePerNft = withdrawFee_;
    }

    /**
     * @dev Update max nft count available per user
     * Only owner has privilege to call this function
     */
    function updateMaxNftsPerUser(uint256 maxLimit_) external onlyOwner {
        require(maxLimit_ > 0, "Invalid limit value");
        _maxNftsPerUser = maxLimit_;
    }

    /**
     * @dev Update reward per block, per nft
     * Only owner has privilege to call this function
     */
    function updateRewardPerBlock(uint256 rewardPerBlock_) external onlyOwner {
        require(rewardPerBlock_ > 0, "Invalid reward per block");
        emit RewardPerBlockUpdated(_rewardPerBlock, rewardPerBlock_);
        _rewardPerBlock = rewardPerBlock_;
    }

    /**
     * @dev Update start block number
     * Only owner has privilege to call this function
     */
    function updateStartBlock(uint256 startBlock_) external onlyOwner {
        require(
            startBlock_ <= _endBlock,
            "Start block must be before end block"
        );
        require(
            startBlock_ > block.number,
            "Start block must be after current block"
        );
        require(_startBlock > block.number, "Staking started already");
        _startBlock = startBlock_;
    }

    /**
     * @dev Update end block number
     * Only owner has privilege to call this function
     */
    function updateEndBlock(uint256 endBlock_) external onlyOwner {
        require(
            endBlock_ >= _startBlock,
            "End block must be after start block"
        );
        require(
            endBlock_ > block.number,
            "End block must be after current block"
        );
        _endBlock = endBlock_;
    }

    

    /**
     * @dev Check if the user staked the nft of token id
     */
    function isStaked(address account_, uint256 tokenId_)
        public
        view
        returns (bool)
    {
        UserInfo storage user = _userInfo[account_];
        return user.stakedNfts.contains(tokenId_);
    }

    /**
     * @dev Get pending reward amount for the account
     */
    function pendingRewards(address account_) public view returns (uint256) {
        UserInfo storage user = _userInfo[account_];

        uint256 fromBlock = user.lastRewardBlock < _startBlock
            ? _startBlock
            : user.lastRewardBlock;
        uint256 toBlock = block.number < _endBlock ? block.number : _endBlock;
        if (toBlock < fromBlock) {
            return user.rewards;
        }

        uint256 amount = toBlock
            .sub(fromBlock)
            .mul(userStakedNFTCount(account_))
            .mul(_rewardPerBlock);

        return user.rewards.add(amount);
    }

    /**
     * @dev Stake nft token ids
     */
    function stake(uint256[] memory tokenIdList_)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        require(
            IERC721(_stakeNftAddress).isApprovedForAll(
                _msgSender(),
                address(this)
            ),
            "Not approve nft to staker address"
        );
        uint256 countToStake = tokenIdList_.length;
        require(
            userStakedNFTCount(_msgSender()).add(countToStake) <=
                _maxNftsPerUser,
            "Exceeds the max limit per user"
        );

        UserInfo storage user = _userInfo[_msgSender()];
        uint256 pendingAmount = pendingRewards(_msgSender());
        if (pendingAmount > 0) {
            uint256 amountSent = safeRewardTransfer(
                _msgSender(),
                pendingAmount
            );
            user.rewards = pendingAmount.sub(amountSent);
            emit Harvested(_msgSender(), amountSent);
        }

        if (countToStake > 0 && _depositFeePerNft > 0) {
            require(
                msg.value >= countToStake.mul(_depositFeePerNft),
                "Insufficient deposit fee"
            );
            _feeAddress.transfer(address(this).balance);
        }

        for (uint256 i = 0; i < countToStake; i++) {
            IERC721(_stakeNftAddress).safeTransferFrom(
                _msgSender(),
                address(this),
                tokenIdList_[i]
            );

            user.stakedNfts.add(tokenIdList_[i]);

            emit Staked(_msgSender(), tokenIdList_[i]);
        }
        user.lastRewardBlock = block.number;
    }

    /**
     * @dev Withdraw nft token ids
     */
    function withdraw(uint256[] memory tokenIdList_)
        external
        payable
        nonReentrant
    {
        UserInfo storage user = _userInfo[_msgSender()];
        uint256 pendingAmount = pendingRewards(_msgSender());
        if (pendingAmount > 0) {
            uint256 amountSent = safeRewardTransfer(
                _msgSender(),
                pendingAmount
            );
            user.rewards = pendingAmount.sub(amountSent);
            emit Harvested(_msgSender(), amountSent);
        }

        uint256 countToWithdraw = tokenIdList_.length;

        if (countToWithdraw > 0 && _withdrawFeePerNft > 0) {
            require(
                msg.value >= countToWithdraw.mul(_withdrawFeePerNft),
                "Insufficient withdraw fee"
            );
            _feeAddress.transfer(address(this).balance);
        }

        for (uint256 i = 0; i < countToWithdraw; i++) {
            require(
                isStaked(_msgSender(), tokenIdList_[i]),
                "Not staked this nft"
            );

            IERC721(_stakeNftAddress).safeTransferFrom(
                address(this),
                _msgSender(),
                tokenIdList_[i]
            );

            user.stakedNfts.remove(tokenIdList_[i]);

            emit Withdrawn(_msgSender(), tokenIdList_[i]);
        }
        user.lastRewardBlock = block.number;
    }

    /**
     * @dev Safe transfer reward to the receiver
     */
    function safeRewardTransfer(address _to, uint256 _amount)
        internal
        returns (uint256)
    {
        require(_to != address(0), "Invalid null address");
        uint256 tokenBalance = IERC20(_rewardTokenAddress).balanceOf(address(this));
        if (_amount == 0 || tokenBalance == 0) {
            return 0;
        }
        if (_amount > tokenBalance) {
            _amount = tokenBalance;
        }
        IERC20(_rewardTokenAddress).safeTransfer(_to, _amount);
        return _amount;
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(address token_, uint256 amount_)
        external
        onlyOwner
    {
        IERC20(token_).safeTransfer(_msgSender(), amount_);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @dev To receive ETH
     */
    receive() external payable {}
}