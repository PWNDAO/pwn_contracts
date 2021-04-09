pragma abicoder v2;
pragma solidity >=0.6.0 <0.8.0;

import "./MultiToken.sol";
import "./PWNVault.sol";
import "./PWNDeed.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PWN is Ownable {
    using MultiToken for MultiToken.Asset;

    PWNDeed public token;
    PWNVault public vault;

    uint256 public minDuration = 7 days;

    event NewDeed(uint8 cat, uint256 id, uint256 amount, address tokenAddress, uint256 expiration, uint256 did);
    event NewOffer(uint8 cat, uint256 amount, address tokenAddress, uint256 did, uint256 toBePaid, bytes32 offer);
    event OfferAccepted(uint256 did, bytes32 offer);
    event PaidBack(uint256 did, bytes32 offer);
    event DeedClaimed(uint256 did);

    constructor(
        address _PWND,
        address _PWNV
    ) 
    Ownable()
    {
        token = PWNDeed(_PWND);
        vault = PWNVault(_PWNV);
    }
    
    // add events
    // sets STATUS =  0
    function newDeed(
        uint8   _cat,
        uint256 _id,
        uint256 _amount,
        address _tokenAddress,
        uint256 _expiration
    ) external returns (uint256) {
        require(_cat < 3, "Unknown token type");
        require(_expiration > (block.timestamp + minDuration));

        uint256 did = token.mint(_cat, _amount, _id, _tokenAddress, _expiration, msg.sender);
        vault.push(token.getDeedAsset(did)); //, "Asset wasn't stored in vault");

        emit NewDeed(_cat, _id, _amount, _tokenAddress, _expiration, did);
        return did;
    }

    function makeOffer(
        uint8 _cat,
        uint256 _amount,
        address _tokenAddress,
        uint256 _did,
        uint256 _toBePaid
    ) external returns (bytes32) {
        require(_did <= token.id(), "Contract not found"); //replace with borrower addres present
        require(token.getDeedStatus(_did) == 0, "Contract can't accept offers");

        bytes32 offer = token.setOffer(_cat, _amount, _tokenAddress, _toBePaid, _did);
        emit NewOffer(_cat, _amount, _tokenAddress, _did, _toBePaid, offer);

        return offer;
    }

    // sets STATUS =  1
    function acceptOffer(
        uint256 _did,
        bytes32 _offer
    ) external returns (bool) {
        require(msg.sender == token.getBorrower(_did), "The deed doesn't belong to the caller");
        require(token.getDeedStatus(_did) == 0);
        require(token.getDeedID(_offer) == _did);

        token.setCredit(_did, _offer);
        address lender = token.getLender(_offer);
        vault.pullProxy(token.getOfferAsset(_offer), lender, msg.sender);

        MultiToken.Asset memory Deed;
        Deed.cat = 3;
        Deed.id = _did;
        Deed.tokenAddress = address(token);

        vault.pullProxy(Deed, msg.sender, lender);
        emit OfferAccepted(_did, _offer);

        return true;
    }

    // sets STATUS =  2
    function payBack(uint256 _did) external returns (bool) {
        require(block.timestamp < token.getExpiration(_did), "Contract expired");
        require(token.getDeedStatus(_did) == 1);

        token.changeStatus(2, _did);

        bytes32 offer = token.getAcceptedOffer(_did);
        MultiToken.Asset memory credit = token.getOfferAsset(offer);
        credit.amount = token.toBePaid(offer);               //override the num of credit given

        vault.pull(token.getDeedAsset(_did), token.getBorrower(_did));
        vault.push(credit);

        emit PaidBack(_did, offer);
        return true;
    }

    // sets STATUS =  2
    function claimDeed(uint256 _did) external returns (bool) {
        require(token.balanceOf(msg.sender, _did) == 1, "Unauthorized caller");
        require(token.getExpiration(_did) < block.timestamp || token.getDeedStatus(_did) == 2, "Contract not yet defaulted");

        if (token.getDeedStatus(_did) == 2) {
            bytes32 offer = token.getAcceptedOffer(_did);
            MultiToken.Asset memory credit = token.getOfferAsset(offer);
            credit.amount = token.toBePaid(offer);
        
            vault.pull(credit, msg.sender);
        } else {
            
            vault.pull(token.getDeedAsset(_did), msg.sender);
        }

        emit DeedClaimed(_did);
        token.burn(_did);
        return true;
    }

}
