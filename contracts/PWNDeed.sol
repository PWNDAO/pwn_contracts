// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.4;

import "@pwnfinance/multitoken/contracts/MultiToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract PWNDeed is ERC1155, Ownable {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    address public PWN;                 // necessary msg.sender for all Deed related manipulations
    uint256 public id;                  // simple DeedID counter
    uint256 private nonce;              // server for offer hash generation

    /**
     * Construct defining a Deed
     * @param status 0 == none/dead || 1 == new/open || 2 == running/accepted offer || 3 == paid back || 4 == expired
     * @param borrower Address of the issuer / borrower - stays the same for entire lifespan of the token
     * @param duration Loan duration in seconds
     * @param expiration Unix timestamp (in seconds) setting up the default deadline
     * @param collateral Consisting of another an `Asset` struct defined in the MultiToken library
     * @param acceptedOffer Hash of the offer which will be bound to the deed
     * @param pendingOffers List of offers made to the Deed
     */
    struct Deed {
        uint8 status;
        address borrower;
        uint32 duration;
        uint40 expiration;
        MultiToken.Asset collateral;
        bytes32 acceptedOffer;
        bytes32[] pendingOffers;
    }

    /**
     * Construct defining an offer
     * @param did Deed ID the offer is bound to
     * @param toBePaid Nn amount to be paid back (borrowed + interest)
     * @param lender Address of the lender to be the loan withdrawn from
     * @param loan Consisting of another an `Asset` struct defined in the MultiToken library
     */
    struct Offer {
        uint256 did;
        uint256 toBePaid;
        address lender;
        MultiToken.Asset loan;
    }

    mapping (uint256 => Deed) public deeds;             // mapping of all Deed data
    mapping (bytes32 => Offer) public offers;           // mapping of all Offer data

    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS DEFINITIONS                           *|
    |*----------------------------------------------------------*/

    event DeedCreated(address indexed assetAddress, MultiToken.Category category, uint256 id, uint256 amount, uint32 duration, uint256 indexed did);
    event OfferMade(address assetAddress, uint256 amount, address indexed lender, uint256 toBePaid, uint256 indexed did, bytes32 offer);
    event DeedRevoked(uint256 did);
    event OfferRevoked(bytes32 offer);
    event OfferAccepted(uint256 did, bytes32 offer);
    event PaidBack(uint256 did, bytes32 offer);
    event DeedClaimed(uint256 did);

    /*----------------------------------------------------------*|
    |*  # MODIFIERS                                             *|
    |*----------------------------------------------------------*/

    modifier onlyPWN() {
        require(msg.sender == PWN, "Caller is not the PWN");
        _;
    }

    /*----------------------------------------------------------*|
    |*  # CONSTRUCTOR & FUNCTIONS                               *|
    |*----------------------------------------------------------*/

    /*
     *  PWN Deed constructor
     *  @dev Creates the PWN Deed token contract - ERC1155 with extra use case specific features
     *  @dev Once the PWN contract is set, you'll have to call `this.setPWN(PWN.address)` for this contract to work
     *  @param _uri Uri to be used for finding the token metadata (https://api.pwn.finance/deed/...)
     */
    constructor(string memory _uri) ERC1155(_uri) Ownable() {

    }

    /*
     *   All contracts of this section can only be called by the PWN contract itself - once set via `setPWN(PWN.address)`
     */

    /**
     * create
     * @dev Creates the PWN Deed token contract - ERC1155 with extra use case specific features
     * @param _assetAddress Address of the asset contract
     * @param _assetCategory Category of the asset - see { MultiToken.sol }
     * @param _duration Loan duration in seconds
     * @param _assetId ID of an ERC721 or ERC1155 token || 0 in case the token doesn't have IDs
     * @param _assetAmount Amount of an ERC20 or ERC1155 token || 0 in case of NFTs
     * @param _owner Address initiating the new Deed
     * @return Deed ID of the newly minted Deed
     */
    function create(
        address _assetAddress,
        MultiToken.Category _assetCategory,
        uint32 _duration,
        uint256 _assetId,
        uint256 _assetAmount,
        address _owner
    ) external onlyPWN returns (uint256) {
        id++;

        Deed storage deed = deeds[id];
        deed.duration = _duration;
        deed.collateral.assetAddress = _assetAddress;
        deed.collateral.category = _assetCategory;
        deed.collateral.id = _assetId;
        deed.collateral.amount = _assetAmount;

        _mint(_owner, id, 1, "");

        deed.status = 1;

        emit DeedCreated(_assetAddress, _assetCategory, _assetId, _assetAmount, _duration, id);

        return id;
    }

    /**
     * revoke
     * @dev Burns a deed token
     * @param _did Deed ID of the token to be burned
     * @param _owner Address of the borrower who issued the Deed
     */
    function revoke(
        uint256 _did,
        address _owner
    ) external onlyPWN {
        require(balanceOf(_owner, _did) == 1, "The deed doesn't belong to the caller");
        require(getDeedStatus(_did) == 1, "Deed can't be revoked at this stage");

        deeds[_did].status = 0;

        emit DeedRevoked(_did);
    }

    /**
     * makeOffer
     * @dev saves an offer object that defines loan terms
     * @dev only ERC20 tokens can be offered as loan
     * @param _assetAddress Address of the asset contract
     * @param _assetAmount Amount of an ERC20 token to be offered as loan
     * @param _lender Address of the asset lender
     * @param _did ID of the Deed the offer should be bound to
     * @param _toBePaid Amount to be paid back by the borrower
     * @return hash of the newly created offer
     */
    function makeOffer(
        address _assetAddress,
        uint256 _assetAmount,
        address _lender,
        uint256 _did,
        uint256 _toBePaid
    ) external onlyPWN returns (bytes32) {
        require(getDeedStatus(_did) == 1, "Deed not accepting offers");

        bytes32 hash = keccak256(abi.encodePacked(_lender, nonce));
        nonce++;

        Offer storage offer = offers[hash];
        offer.loan.assetAddress = _assetAddress;
        offer.loan.amount = _assetAmount;
        offer.toBePaid = _toBePaid;
        offer.lender = _lender;
        offer.did = _did;

        deeds[_did].pendingOffers.push(hash);

        emit OfferMade(_assetAddress, _assetAmount, _lender, _toBePaid, _did, hash);

        return hash;
    }

    /**
     * revokeOffer
     * @dev function to remove a pending offer
     * @dev This only removes the offer representation but it doesn't remove the offer from a list of pending offers.
     *         The offers associated with a deed has to be filtered on the front end to only list the valid ones.
     *         No longer existent offers will simply return 0 if prompted about their DID.
     * @param _offer Hash identifying an offer
     * @param _lender Address of the lender who made the offer
     * @dev TODO: consider ways to remove the offer from the pending offers array / maybe replace for a mapping
     */
    function revokeOffer(
        bytes32 _offer,
        address _lender
    ) external onlyPWN {
        require(offers[_offer].lender == _lender, "This address didn't create the offer");
        require(getDeedStatus(offers[_offer].did) == 1, "Can only remove offers from open Deeds");

        delete offers[_offer];

        emit OfferRevoked(_offer);
    }

    /**
     * acceptOffer
     * @dev function to set accepted offer
     * @param _did ID of the Deed the offer should be bound to
     * @param _offer Hash identifying an offer
     * @param _owner Address of the borrower who issued the Deed
     */
    function acceptOffer(
        uint256 _did,
        bytes32 _offer,
        address _owner
    ) external onlyPWN {
        require(balanceOf(_owner, _did) == 1, "The deed doesn't belong to the caller");
        require(getDeedStatus(_did) == 1, "Deed can't accept more offers");

        Deed storage deed = deeds[_did];
        deed.borrower = _owner;
        deed.expiration = uint40(block.timestamp) + deed.duration;
        deed.acceptedOffer = _offer;
        delete deed.pendingOffers;
        deed.status = 2;

        emit OfferAccepted(_did, _offer);
    }

    /**
     * repayLoan
     * @dev function to make proper state transition
     * @param _did ID of the Deed which is paid back
     */
    function repayLoan(uint256 _did) external onlyPWN {
        require(getDeedStatus(_did) == 2, "Deed doesn't have an accepted offer to be paid back");

        deeds[_did].status = 3;

        emit PaidBack(_did, deeds[_did].acceptedOffer);
    }

    /**
     * claim
     * @dev function that would burn the deed token if the token is in paidBack or expired state
     * @param _did ID of the Deed which is claimed
     * @param _owner Address of the deed token owner
     */
    function claim(
        uint256 _did,
        address _owner
    ) external onlyPWN {
        require(balanceOf(_owner, _did) == 1, "Caller is not the deed owner");
        require(getDeedStatus(_did) >= 3, "Deed can't be claimed yet");

        deeds[_did].status = 0;

        emit DeedClaimed(_did);
    }

    /**
     * burn
     * @dev function that would burn the deed token if the token is in dead state
     * @param _did ID of the Deed which is burned
     * @param _owner Address of the deed token owner
     */
    function burn(
        uint256 _did,
        address _owner
    ) external onlyPWN {
        require(balanceOf(_owner, _did) == 1, "Caller is not the deed owner");
        require(deeds[_did].status == 0, "Deed can't be burned at this stage");

        delete deeds[_did];
        _burn(_owner, _did, 1);
    }

    /*----------------------------------------------------------*|
    |*  ## VIEW FUNCTIONS                                       *|
    |*----------------------------------------------------------*/

    /*--------------------------------*|
    |*  ## VIEW FUNCTIONS - DEEDS     *|
    |*--------------------------------*/

    /**
     * getDeedStatus
     * @dev used in contract calls & status checks and also in UI for elementary deed status categorization
     * @param _did Deed ID checked for status
     * @return a status number
     */
    function getDeedStatus(uint256 _did) public view returns (uint8) {
        if (deeds[_did].expiration > 0 && deeds[_did].expiration < block.timestamp && deeds[_did].status != 3) {
            return 4;
        } else {
            return deeds[_did].status;
        }
    }

    /**
     * getExpiration
     * @dev utility function to find out exact expiration time of a particular Deed
     * @dev for simple status check use `this.getDeedStatus(did)` if `status == 4` then Deed has expired
     * @param _did Deed ID to be checked
     * @return unix time stamp in seconds
     */
    function getExpiration(uint256 _did) public view returns (uint40) {
        return deeds[_did].expiration;
    }

    /**
     * getDuration
     * @dev utility function to find out loan duration period of a particular Deed
     * @param _did Deed ID to be checked
     * @return loan duration period in seconds
     */
    function getDuration(uint256 _did) public view returns (uint32) {
        return deeds[_did].duration;
    }

    /**
     * getBorrower
     * @dev utility function to find out a borrower address of a particular Deed
     * @param _did Deed ID to be checked
     * @return address of the borrower
     */
    function getBorrower(uint256 _did) public view returns (address) {
        return deeds[_did].borrower;
    }

    /**
     * getDeedCollateral
     * @dev utility function to find out collateral asset of a particular Deed
     * @param _did Deed ID to be checked
     * @return Asset construct - for definition see { MultiToken.sol }
     */
    function getDeedCollateral(uint256 _did) public view returns (MultiToken.Asset memory) {
        return deeds[_did].collateral;
    }

    /**
     * getOffers
     * @dev utility function to get a list of all pending offers of a Deed
     * @param _did Deed ID to be checked
     * @return a list of offer hashes
     */
    function getOffers(uint256 _did) public view returns (bytes32[] memory) {
        return deeds[_did].pendingOffers;
    }

    /**
     * getAcceptedOffer
     * @dev used to get a list of made offers to be queried in the UI - needs additional check for re-validating each offer
     * @dev revalidation requires checking if the lender has sufficient balance and approved the asset
     * @param _did Deed ID being queried for offers
     * @return Hash of the accepted offer
     */
    function getAcceptedOffer(uint256 _did) public view returns (bytes32) {
        return deeds[_did].acceptedOffer;
    }

    /*--------------------------------*|
    |*  ## VIEW FUNCTIONS - OFFERS    *|
    |*--------------------------------*/

    /**
     * getDeedID
     * @dev utility function to find out which Deed is an offer associated with
     * @param _offer Offer hash of an offer to be prompted
     * @return Deed ID
     */
    function getDeedID(bytes32 _offer) public view returns (uint256) {
        return offers[_offer].did;
    }

    /**
     * getOfferLoan
     * @dev utility function that returns the loan asset of a particular offer
     * @param _offer Offer hash of an offer to be prompted
     * @return Asset construct - for definition see { MultiToken.sol }
     */
    function getOfferLoan(bytes32 _offer) public view returns (MultiToken.Asset memory) {
        return offers[_offer].loan;
    }

    /**
     * toBePaid
     * @dev quick query of the total amount to be paid to an offer
     * @param _offer Offer hash of an offer to be prompted
     * @return Amount to be paid back
     */
    function toBePaid(bytes32 _offer) public view returns (uint256) {
        return offers[_offer].toBePaid;
    }

    /**
     * getLender
     * @dev utility function to find out a lender address of a particular offer
     * @param _offer Offer hash of an offer to be prompted
     * @return Address of the lender
     */
    function getLender(bytes32 _offer) public view returns (address) {
        return offers[_offer].lender;
    }

    /*--------------------------------*|
    |*  ## SETUP FUNCTIONS            *|
    |*--------------------------------*/

    /**
     * setPWN
     * @dev An essential setup function. Has to be called once PWN contract was deployed
     * @param _address Identifying the PWN contract
     */
    function setPWN(address _address) external onlyOwner {
        PWN = _address;
    }
}
