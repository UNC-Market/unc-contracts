// Multiple Fixed Price Marketplace contract
// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./SingleNFTStaking.sol";

interface ISingleNFTStaking {
	function initialize(string memory _name, string memory _uri, address creator, uint256 royalties, bool bPublic) external;	
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
    
	event SingleNFTStakingCreated(address collection_address, address owner, string name, string uri, uint256 royalties, bool isPublic);
    
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

	function deleteSubscription(uint256 _subscriptionsId) external onlyOwner {
		require(_subscriptions[_subscriptionsId].bValid, "not exist");
        _subscriptions[_subscriptionsId].bValid = false;        
        
        _subscriptionIndices.remove(_subscriptionsId);
        emit SubscriptionDeleted(_subscriptionsId);
    }

	function updateSubscription(uint256 _subscriptionsId, string memory _name, uint256 _period, uint256 _price) external onlyOwner {        
        require(_subscriptions[_subscriptionsId].bValid, "not exist");

        _subscriptions[_subscriptionsId].name = _name;
		_subscriptions[_subscriptionsId].period = _period;
		_subscriptions[_subscriptionsId].price = _price;    
        
        emit SubscriptionUpdated(_subscriptionsId, _subscriptions[_subscriptionsId]);
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

	function allSubscriptions() view public returns(Subscription[] memory cards) {
        uint256 cardsCount = cardKeyCount();
        cards = new Card[](cardsCount);        

        for(uint i = 0; i < cardsCount; i++) {
            cards[i] = _cards[cardKeyWithIndex(i)];           
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
        emit SubscriptionDeleted(_subscriptionsId);
    }

	function aprCount() view public returns(uint256) {
        return _aprs.length();
    }

    function aprWithIndex(uint256 index) view public returns(bytes32) {
        return _aprs.at(index);
    }


	function createSingleNFTStaking(string memory _name, string memory _uri, uint256 royalties, bool bPublic) external returns(address collection) {
		if(bPublic){
			require(owner() == msg.sender, "Only owner can create public collection");	
		}		
		bytes memory bytecode = type(MultipleNFT).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_uri, _name, block.timestamp));
        assembly {
            collection := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        INFTCollection(collection).initialize(_name, _uri, msg.sender, royalties, bPublic);
		collections.push(collection);
		emit MultiCollectionCreated(collection, msg.sender, _name, _uri, royalties, bPublic);
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