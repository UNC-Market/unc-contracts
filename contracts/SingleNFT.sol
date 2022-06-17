// SingleNFT token
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface INFTFactory {
	function getMintFee() external view returns (uint256);	
}

contract SingleNFT is ERC721 {
    using SafeMath for uint256;    

	bool private initialisable;
    string public collection_name;
    string private collection_uri;
    bool public isPublic;
    address public factory;
    address public owner;

    struct Item {
        uint256 id;
        address creator;
        string uri;       
    }
    uint256 public currentID;    
    mapping (uint256 => Item) public Items;

    event CollectionUriUpdated(string collection_uri);    
    event CollectionNameUpdated(string collection_name);
    event TokenUriUpdated(uint256 id, string uri);

    event ItemCreated(uint256 id, address creator, string uri);
    event Burned(address owner, uint nftID);

    constructor() ERC721("SingleNFT","ST") {
        factory = msg.sender;
        initialisable = true;	
    }

    /**
		Initialize from Swap contract
	 */
    function initialize(
        string memory _name,
        string memory _uri,
        address creator,
        bool bPublic
    ) external {
        require(msg.sender == factory, "Only for factory");
        require(initialisable, "initialize() can be called only one time.");
		initialisable = false;
        
        collection_uri = _uri;
        collection_name = _name;
        owner = creator;
        isPublic = bPublic;
    }

    
    /**
		Change Collection Information
	 */
    function setCollectionURI(string memory newURI) external onlyOwner {
        collection_uri = newURI;
        emit CollectionUriUpdated(newURI);
    }
    function contractURI() external view returns (string memory) {
        return collection_uri;
    }

    function setName(string memory newname) external onlyOwner {
        collection_name = newname;
        emit CollectionNameUpdated(newname);
    }

    
    /**
		Change & Get Item Information
	 */
    function addItem(string memory _tokenURI) external payable returns (uint256){
        uint256 mintFee = INFTFactory(factory).getMintFee();
        require(msg.value >= mintFee, "insufficient fee");	
        if (mintFee > 0) {
            payable(factory).transfer(mintFee);
        }

        currentID = currentID.add(1);        
        _safeMint(msg.sender, currentID);
        Items[currentID] = Item(currentID, msg.sender, _tokenURI);
        emit ItemCreated(currentID, msg.sender, _tokenURI);
        return currentID;
    }

    function burn(uint _tokenId) external returns (bool)  {
        require(_exists(_tokenId), "Token ID is invalid");
        require(ERC721.ownerOf(_tokenId) == msg.sender, "only owner can burn");
        _burn(_tokenId);
        emit Burned(msg.sender,_tokenId);
        return true;
    }

    function setTokenURI(uint256 _tokenId, string memory _newURI)
        external
        creatorOnly(_tokenId)
    {
        Items[_tokenId].uri = _newURI;
        emit TokenUriUpdated( _tokenId, _newURI);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return Items[tokenId].uri;
    }   


    function transferOwner(address _newOwner) external onlyOwner {
        owner = _newOwner;        
    } 

    modifier onlyOwner() {
        require(owner == _msgSender(), "caller is not the owner");
        _;
    }
    /**
     * @dev Require _msgSender() to be the creator of the token id
     */
    modifier creatorOnly(uint256 _id) {
        require(
            Items[_id].creator == _msgSender(),
            "ERC721Tradable#creatorOnly: ONLY_CREATOR_ALLOWED"
        );
        _;
    }
}
