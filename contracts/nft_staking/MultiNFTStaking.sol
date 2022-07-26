// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
// import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "./NFTStaking.sol";

contract MultiNFTStaking is NFTStaking, ERC1155Holder {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    struct UserInfo {
        EnumerableSet.UintSet stakedNfts; // staked nft tokenid array
        uint256 rewards;
        uint256 lastRewardTimestamp;
    }

    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) private _userInfo;

    // nft amount of each (user, tokenId).
    mapping(bytes32 => uint256) private _nftAmounts;

    constructor() {}

    function viewUserInfo(address account_)
        external
        view
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
        uint256 stakedNftCount = user.stakedNfts.length();
        totalstakedNftCount = userStakedNFTAmount(account_);
        if (stakedNftCount == 0) {
            // Return an empty array
            stakedNfts = new uint256[](0);
            stakedNftAmounts = new uint256[](0);
        } else {
            stakedNfts = new uint256[](stakedNftCount);
            stakedNftAmounts = new uint256[](stakedNftCount);
            uint256 index;
            for (index = 0; index < stakedNftCount; index++) {
                uint256 stakedNftId = user.stakedNfts.at(index);
                bytes32 key = nftKeyOfUser(account_, stakedNftId);
                uint256 nftAmount = _nftAmounts[key];

                stakedNfts[index] = stakedNftId;
                stakedNftAmounts[index] = nftAmount;
            }
        }
    }

    function nftKeyOfUser(address _userAddress, uint256 _tokenId)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_userAddress, _tokenId));
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

    function userStakedNFTAmount(address account_)
        public
        view
        returns (uint256)
    {
        UserInfo storage user = _userInfo[account_];
        uint256 stakedNftCount = user.stakedNfts.length();
        uint256 totalstakedNftCount = 0;
        if (stakedNftCount > 0) {
            uint256 index;
            for (index = 0; index < stakedNftCount; index++) {
                uint256 stakedNftId = user.stakedNfts.at(index);
                bytes32 key = nftKeyOfUser(account_, stakedNftId);
                uint256 nftAmount = _nftAmounts[key];
                totalstakedNftCount = totalstakedNftCount.add(nftAmount);
            }
        }
        return totalstakedNftCount;
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

        uint256 totalstakedNftCount = userStakedNFTAmount(account_);

        uint256 amount = toTimestamp
            .sub(fromTimestamp)
            .mul(totalstakedNftCount)
            .mul(_rewardPerTimestamp);

        return user.rewards.add(amount);
    }

    /**
     * @dev Stake nft token ids
     */
    function stake(uint256[] memory tokenIdList_, uint256[] memory amountList_)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        require(
            IERC1155(_stakeNftAddress).isApprovedForAll(
                _msgSender(),
                address(this)
            ),
            "Not approve nft to staker address"
        );
        require(
            tokenIdList_.length == amountList_.length,
            "Invalid Token ids"
        );

        uint256 countToStake = tokenIdList_.length;
        uint256 amountToStake = 0;
        if (countToStake > 0) {
            for (uint256 i = 0; i < countToStake; i++) {
                amountToStake = amountToStake.add(amountList_[i]);
            }
        }

        UserInfo storage user = _userInfo[_msgSender()];

        uint256 stakedNftCount = user.stakedNfts.length();
        uint256 stakedNftAmount = userStakedNFTAmount(_msgSender());
        require(
            stakedNftAmount.add(amountToStake) <= _maxNftsPerUser,
            "Exceeds the max limit per user"
        );
        require(
            _totalStakedNfts.add(amountToStake) <= _maxStakedNfts,
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

        if (amountToStake > 0 && _depositFeePerNft > 0) {
            require(
                msg.value >= amountToStake.mul(_depositFeePerNft),
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
            IERC1155(_stakeNftAddress).safeTransferFrom(
                _msgSender(),
                address(this),
                tokenIdList_[i],
                amountList_[i],
                "stake"
            );
            if (!isStaked(_msgSender(), tokenIdList_[i])) {
                user.stakedNfts.add(tokenIdList_[i]);
            }
            
            bytes32 key = nftKeyOfUser(_msgSender(), tokenIdList_[i]);
            _nftAmounts[key] = _nftAmounts[key] + amountList_[i];

            emit Staked(_msgSender(), tokenIdList_[i], amountList_[i]);
        }

        _totalStakedNfts = _totalStakedNfts.add(amountToStake);
        user.lastRewardTimestamp = block.timestamp;
    }

    /**
     * @dev Withdraw nft token ids
     */
    function withdraw(uint256[] memory tokenIdList_, uint256[] memory amountList_)
        external
        payable
        nonReentrant
    {
        require(
            tokenIdList_.length == amountList_.length,
            "Invalid Token ids"
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

        uint256 countToWithdraw = tokenIdList_.length;
        uint256 amountToWithdraw = 0;
        if (countToWithdraw > 0) {
            for (uint256 i = 0; i < countToWithdraw; i++) {
                amountToWithdraw = amountToWithdraw.add(amountList_[i]);
            }
        }

        if (amountToWithdraw > 0 && _withdrawFeePerNft > 0) {
            require(
                msg.value >= amountToWithdraw.mul(_withdrawFeePerNft),
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
            bytes32 key = nftKeyOfUser(_msgSender(), tokenIdList_[i]);
            uint256 nftAmounts = _nftAmounts[key];
            require(
                (nftAmounts > 0 && nftAmounts >= amountList_[i]),
                "insufficient withdraw amount"
            );
            IERC1155(_stakeNftAddress).safeTransferFrom(
                address(this),
                _msgSender(),
                tokenIdList_[i],
                amountList_[i],
                "Withdraw"
            );
            if (nftAmounts == amountList_[i]) {
                user.stakedNfts.remove(tokenIdList_[i]);
            }
            _nftAmounts[key] = nftAmounts - amountList_[i];           

            emit Withdrawn(_msgSender(), tokenIdList_[i], amountList_[i]);
        }
        user.lastRewardTimestamp = block.timestamp;
    }
}
