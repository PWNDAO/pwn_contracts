pragma abicoder v2;
pragma solidity >=0.6.0 <0.8.0;

import "./MultiToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155Pausable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155Burnable.sol";
//import "@openzeppelin/contracts/token/ERC1155/ERC1155Holder.sol";

contract PWNDeed is ERC1155, ERC1155Burnable, Ownable  {
    using MultiToken for MultiToken.Asset;

    address public PWN;
    uint256 public id;
    uint256 private nonce;

    struct Deed {
        uint8 status;
        uint256 expiration;
        address borrower;
        MultiToken.Asset asset;
        bytes32 acceptedOffer;
        bytes32[] pendingOffers;
    }

    struct Offer {
        uint256 deedID;
        uint256 toBePaid;
        address lender;
        MultiToken.Asset asset;
    }                 
    
    mapping (uint256 => Deed) public deeds;
    mapping (bytes32 => Offer) public offers;

    modifier onlyPWN() {
        require(msg.sender == PWN);
        _;
    }

    constructor(
        string memory _uri
    ) 
    ERC1155(_uri)
    Ownable()
    {
    }
    
    function mint(
        uint8 _cat,
        uint256 _amount,
        uint256 _id,
        address _tokenAddress,
        uint256 _expiration, 
        address _borrower
    ) 
        external
        onlyPWN
        returns (uint256)
    {
        id++;
        deeds[id].status = 0;
        deeds[id].expiration = _expiration;
        deeds[id].borrower = _borrower;
        deeds[id].asset.cat = _cat;
        deeds[id].asset.amount = _amount;
        deeds[id].asset.id = _id;
        deeds[id].asset.tokenAddress = _tokenAddress;

        _mint(_borrower, id, 1, "");
        return id;
    }

    function burn(
        uint256 _id
    ) 
        external 
    {
        delete deeds[_id];
    }

    function setOffer(
        uint8 _cat,
        uint256 _amount,
        address _tokenAddress,
        uint256 _toBePaid,
        uint256 _did
    ) 
        external
        onlyPWN
        returns (bytes32) 
    {
        bytes32 hash = keccak256(abi.encodePacked(msg.sender,nonce));
        nonce++;

        offers[hash].asset.cat = _cat;
        offers[hash].asset.amount = _amount;
        offers[hash].asset.tokenAddress = _tokenAddress;
        offers[hash].toBePaid = _toBePaid;
        offers[hash].lender = msg.sender;
        offers[hash].deedID = _did;
        
        deeds[_did].pendingOffers.push(hash);
        return hash;
    }

    function setCredit(
        uint256 _id, 
        bytes32 _offer
    ) 
        external
        onlyPWN
    {
        deeds[_id].status = 1;
        deeds[_id].acceptedOffer = _offer;

        delete deeds[_id].pendingOffers;
        // TODO: maybe iterate through pending offers & delete them one by one
    }

    function changeStatus(
        uint8 _status, 
        uint256 _id
    ) 
        external
        onlyPWN
    {
        deeds[_id].status = _status;
    }

    // TODO: token transferable only if its status > 0
    //    function transfer() external {} //override so only status > 0 can be transfered
    //    function transferFrom() external {} //override so only status > 0 can be transfered

    function getAcceptedOffer(uint256 _id) public view returns (bytes32) {
        return deeds[_id].acceptedOffer;
    }

    function getOfferAsset(bytes32 _offer) public view returns (MultiToken.Asset memory) {
        return offers[_offer].asset;
    }

    function toBePaid(bytes32 _offer) public view returns (uint256) {
        return offers[_offer].toBePaid;
    }

    function getDeedStatus(uint256 _id) public view returns (uint8) {
        return deeds[_id].status;
    }

    function getDeedAsset(uint256 _id) public view returns (MultiToken.Asset memory) {
        return deeds[_id].asset;
    }

    function getBorrower(uint256 _id) public view returns (address) {
        return deeds[_id].borrower;
    }

    function getLender(bytes32 _offer) public view returns (address) {
        return offers[_offer].lender;
    }

    function getExpiration(uint256 _id) public view returns (uint256) {
        return deeds[_id].expiration;
    }

    function getDeedID(bytes32 _offer) public view returns (uint256) {
        return offers[_offer].deedID;
    }

    function getOffers(uint256 _id) public view returns (bytes32[] memory) {
        return deeds[_id].pendingOffers;
    }

    function setPWN(address _address) external onlyOwner {
        PWN = _address;
    }

}
