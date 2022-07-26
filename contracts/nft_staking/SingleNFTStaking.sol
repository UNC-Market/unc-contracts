// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "./NFTStaking.sol";

contract SingleNFTStaking is NFTStaking, IERC721Receiver {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    struct UserInfo {
        EnumerableSet.UintSet stakedNfts;
        uint256 rewards;
        uint256 lastRewardTimestamp;
    }

    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) private _userInfo;
    

    constructor() {        
    }

    function viewUserInfo(address account_)
        public
        view
        override
        returns (
            uint256[] memory stakedNfts,
            uint256[] memory stakedNftAmounts,
            uint256 totalstakedNftCount,
            uint256 rewards,
            uint256 lastRewardTimestamp
        )
    {
        UserInfo storage user = _userInfo[account_];
        rewards = user.rewards;
        lastRewardTimestamp = user.lastRewardTimestamp;
        totalstakedNftCount = user.stakedNfts.length();
        if (totalstakedNftCount == 0) {
            // Return an empty array
            stakedNfts = new uint256[](0);
            stakedNftAmounts = new uint256[](0);
        } else {
            stakedNfts = new uint256[](totalstakedNftCount);
            stakedNftAmounts = new uint256[](totalstakedNftCount);
            uint256 index;
            for (index = 0; index < totalstakedNftCount; index++) {
                stakedNfts[index] = user.stakedNfts.at(index);
                stakedNftAmounts[index] = 1;
            }
        }
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

        uint256 fromTimestamp = user.lastRewardTimestamp < _startTime
            ? _startTime
            : user.lastRewardTimestamp;
        uint256 toTimestamp = block.timestamp < _endTime
            ? block.timestamp
            : _endTime;
        if (toTimestamp < fromTimestamp) {
            return user.rewards;
        }

        uint256 stakedNftCount = user.stakedNfts.length();

        uint256 amount = toTimestamp.sub(fromTimestamp).mul(stakedNftCount).mul(
            _rewardPerTimestamp
        );

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
        UserInfo storage user = _userInfo[_msgSender()];
        uint256 stakedNftCount = user.stakedNfts.length();
        require(
            stakedNftCount.add(countToStake) <= _maxNftsPerUser,
            "Exceeds the max limit per user"
        );
        require(
            _totalStakedNfts.add(countToStake) <= _maxStakedNfts,
            "Exceeds the max limit"
        );

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
            uint256 adminFeePercent = INFTStakingFactory(factory)
                .getAdminFeePercent();
            uint256 creatorFeePercent = PERCENTS_DIVIDER.sub(adminFeePercent);
            address factoryOwner = INFTStakingFactory(factory).owner();

            payable(factoryOwner).transfer(
                msg.value.mul(adminFeePercent).div(PERCENTS_DIVIDER)
            );
            payable(_creatorAddress).transfer(
                msg.value.mul(creatorFeePercent).div(PERCENTS_DIVIDER)
            );
        }

        for (uint256 i = 0; i < countToStake; i++) {
            IERC721(_stakeNftAddress).safeTransferFrom(
                _msgSender(),
                address(this),
                tokenIdList_[i]
            );

            user.stakedNfts.add(tokenIdList_[i]);
            emit Staked(_msgSender(), tokenIdList_[i], 1);
        }
        _totalStakedNfts = _totalStakedNfts.add(countToStake);
        user.lastRewardTimestamp = block.timestamp;
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
            uint256 adminFeePercent = INFTStakingFactory(factory)
                .getAdminFeePercent();
            uint256 creatorFeePercent = PERCENTS_DIVIDER.sub(adminFeePercent);
            address factoryOwner = INFTStakingFactory(factory).owner();

            payable(factoryOwner).transfer(
                msg.value.mul(adminFeePercent).div(PERCENTS_DIVIDER)
            );
            payable(_creatorAddress).transfer(
                msg.value.mul(creatorFeePercent).div(PERCENTS_DIVIDER)
            );
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

            emit Withdrawn(_msgSender(), tokenIdList_[i], 1);
        }
        user.lastRewardTimestamp = block.timestamp;
    }

    
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
