// Multiple Fixed Price Marketplace contract
// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./MultipleNFT.sol";
import "./SingleNFT.sol";

interface INFTCollection {
	function initialize(string memory _name, string memory _uri, address creator, uint256 royalties, bool bPublic) external;	
}

contract NFTFactory is Ownable {
    using SafeMath for uint256;

    address[] public collections;
	uint256 private mintFee;	
	
	/** Events */
    event MultiCollectionCreated(address collection_address, address owner, string name, string uri, uint256 royalties, bool isPublic);
    event SingleCollectionCreated(address collection_address, address owner, string name, string uri, uint256 royalties, bool isPublic);
    
	constructor () {		
		mintFee = 0 ether;		
	}	

	function getMintFee() external view returns (uint256) {
        return mintFee;
    }

	function setMintFee(uint256 _mintFee) external onlyOwner {
       	mintFee = _mintFee;
    }

	function createMultipleCollection(string memory _name, string memory _uri, uint256 royalties, bool bPublic) external returns(address collection) {
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

	function createSingleCollection(string memory _name, string memory _uri, uint256 royalties, bool bPublic) external returns(address collection) {
		if(bPublic){
			require(owner() == msg.sender, "Only owner can create public collection");	
		}		
		bytes memory bytecode = type(SingleNFT).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_uri, _name, block.timestamp));
        assembly {
            collection := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        INFTCollection(collection).initialize(_name, _uri, msg.sender, royalties, bPublic);
		collections.push(collection);
		
		emit SingleCollectionCreated(collection, msg.sender, _name, _uri, royalties, bPublic);
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