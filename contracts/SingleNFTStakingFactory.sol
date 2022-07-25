// Multiple Fixed Price Marketplace contract
// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./SingleNFTStaking.sol";

interface ISingleNFTStaking {
	function initialize(
		address _stakeNftAddress, 
		address _rewardTokenAddress,
		uint256 _stakeNftPrice,
		uint256 _apr,
		address _creatorAddress,
		uint256 _maxStakedNfts,
		uint256 _maxNftsPerUser,
		uint256 _depositFeePerNft,
		uint256 _withdrawFeePerNft,
		uint256 _startTime,
		uint256 _endTime) external;	
}

contract SingleNFTStakingFactory is Ownable {
    using SafeMath for uint256;
	using EnumerableSet for EnumerableSet.UintSet;

    address[] public stakings;
	address private adminFeeAddress;
	uint256 private adminFeePercent = 100; // 10 %
	uint256 private depositFeePerNft = 0 ether;	
	uint256 private withdrawFeePerNft= 0 ether;

	struct Subscription {
        uint256 id;
        string name;
        uint256 period; // calculate with time interval
        uint256 price;
		bool bValid;             
    }

	uint256 public currentSubscriptionsId = 0;
	mapping (uint256 => Subscription) private _subscriptions;	 
	EnumerableSet.UintSet private _subscriptionIndices;

	EnumerableSet.UintSet private _aprs;	
	
	/** Events */
	event SubscriptionCreated(Subscription subscription);
	event SubscriptionDeleted(uint256 subscriptionsId);
	event SubscriptionUpdated(uint256 subscriptionsId, Subscription subscription);
    
	event SingleNFTStakingCreated(
		address _stake_address, 
		address _stakeNftAddress, 
		address _rewardTokenAddress,
		uint256 _stakeNftPrice,
		uint256 _apr,
		address _creatorAddress,
		uint256 _maxStakedNfts,
		uint256 _maxNftsPerUser,
		uint256 _depositFeePerNft,
		uint256 _withdrawFeePerNft,
		uint256 _startTime,
		uint256 _endTime);
    
	constructor (address _adminFeeAddress) {
		adminFeeAddress = _adminFeeAddress;		
	}	

	function getAdminFeeAddress() external view returns (address) {
        return adminFeeAddress;
    }
	function setAdminFeeAddress(address _adminFeeAddress) external onlyOwner {
       	adminFeeAddress = _adminFeeAddress;
    }

	function getAdminFeePercent() external view returns (uint256) {
        return adminFeePercent;
    }
	function setAdminFeePercent(uint256 _adminFeePercent) external onlyOwner {
       	adminFeePercent = _adminFeePercent;
    }


	function getDepositFeePerNft() external view returns (uint256) {
        return depositFeePerNft;
    }
	function setDepositFeePerNft(uint256 _depositFeePerNft) external onlyOwner {
       	depositFeePerNft = _depositFeePerNft;
    }

	function getWithdrawFeePerNft() external view returns (uint256) {
        return withdrawFeePerNft;
    }
	function setWithdrawFeePerNft(uint256 _withdrawFeePerNft) external onlyOwner {
       	withdrawFeePerNft = _withdrawFeePerNft;
    }


	/**
		Subscription Management
	 */
	function addSubscription(string memory _name, uint256 _period, uint256 _price) external onlyOwner {        
        currentSubscriptionsId = currentSubscriptionsId.add(1);    
        _subscriptions[currentSubscriptionsId].id = currentSubscriptionsId;
        _subscriptions[currentSubscriptionsId].name = _name;
		_subscriptions[currentSubscriptionsId].period = _period;
		_subscriptions[currentSubscriptionsId].price = _price;  
		_subscriptions[currentSubscriptionsId].bValid = true;   
        
        _subscriptionIndices.add(currentSubscriptionsId);
        emit SubscriptionCreated(_subscriptions[currentSubscriptionsId]);
    }

	function deleteSubscription(uint256 _subscriptionId) external onlyOwner {
		require(_subscriptions[_subscriptionId].bValid, "not exist");
        _subscriptions[_subscriptionId].bValid = false;        
        
        _subscriptionIndices.remove(_subscriptionId);
        emit SubscriptionDeleted(_subscriptionId);
    }

	function updateSubscription(uint256 _subscriptionId, string memory _name, uint256 _period, uint256 _price) external onlyOwner {        
        require(_subscriptions[_subscriptionId].bValid, "not exist");

        _subscriptions[_subscriptionId].name = _name;
		_subscriptions[_subscriptionId].period = _period;
		_subscriptions[_subscriptionId].price = _price;    
        
        emit SubscriptionUpdated(_subscriptionId, _subscriptions[_subscriptionId]);
    }

	function subscriptionCount() view public returns(uint256) {
        return _subscriptionIndices.length();
    }

    function subscriptionIdWithIndex(uint256 index) view public returns(bytes32) {
        return _subscriptionIndices.at(index);
    }

	function viewSubscriptionInfo(uint256 _subscriptionId) external view returns (Subscription) {
		return _subscriptions[_subscriptionId];
	}

	function allSubscriptions() view public returns(Subscription[] memory scriptions) {
        uint256 scriptionCount = subscriptionCount();
        scriptions = new Subscription[](scriptionCount);        

        for(uint i = 0; i < scriptionCount; i++) {
            scriptions[i] = _subscriptions[subscriptionIdWithIndex(i)];           
        }
    }



	/**
		APR Management
	 */
	function addApr(uint256 _value) external onlyOwner {      
        _aprs.add(_value);
        emit SubscriptionCreated(_subscriptions[currentSubscriptionsId]);
    }

	function deleteApr(uint256 _value) external onlyOwner {		
        _aprs.remove(_value);
        emit SubscriptionDeleted(_subscriptionId);
    }

	function aprCount() view public returns(uint256) {
        return _aprs.length();
    }

    function aprWithIndex(uint256 index) view public returns(bytes32) {
        return _aprs.at(index);
    }


	function createSingleNFTStaking(
		uint256 _subscriptionId, 
		uint256 _aprIndex, 
		address _stakeNftAddress, 
		address _rewardTokenAddress, 
		uint256 _stakeNftPrice, 
		uint256 _maxStakedNfts,
		uint256 _maxNftsPerUser) external payable returns(address staking) {

		require(_subscriptions[_subscriptionId].bValid, "not exist");

		Subscription _subscription = _subscriptions[_subscriptionId];
		uint256 _apr = _aprs.at(_aprIndex);
		require(msg.value >= _subscription.price, "insufficient fee");
				
		bytes memory bytecode = type(SingleNFTStaking).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_uri, _name, block.timestamp));
        assembly {
            staking := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ISingleNFTStaking(staking).initialize(
			_stakeNftAddress, 
			_rewardTokenAddress,
			_stakeNftPrice,
			_apr,
			msg.sender,
			_maxStakedNfts,
			_maxNftsPerUser,
			depositFeePerNft,
			withdrawFeePerNft,
			block.timestamp,
			block.timestamp.add(_subscription.period));
			
		stakings.push(staking);

		emit SingleNFTStakingCreated(
			staking,
			_stakeNftAddress, 
			_rewardTokenAddress,
			_stakeNftPrice,
			_apr,
			_creatorAddress,
			_maxStakedNfts,
			_maxNftsPerUser,
			_depositFeePerNft,
			_withdrawFeePerNft,
			_startTime,
			_endTime);
	}

	function withdrawBNB() external onlyOwner {
		uint balance = address(this).balance;
		require(balance > 0, "insufficient balance");
		payable(msg.sender).transfer(balance);
	}

	/**
     * @dev To receive ETH
     */
    receive() external payable {}
}