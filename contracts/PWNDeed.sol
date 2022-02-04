// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "@pwnfinance/multitoken/contracts/MultiToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract PWNDeed is ERC1155, Ownable {

    /*----------------------------------------------------------*|
    |*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
    |*----------------------------------------------------------*/

    /**
     * Necessary msg.sender for all Deed related manipulations
     */
    address public PWN;

    /**
     * Incremental DeedID counter
     */
    uint256 public id;

    /**
     * EIP-1271 valid signature magic value
     */
    bytes4 constant internal EIP1271_VALID_SIGNATURE = 0x1626ba7e;

    /**
     * EIP-712 offer struct type hash
     */
    bytes32 constant internal OFFER_TYPEHASH = keccak256(
        "Offer(MultiTokenAsset collateral,MultiTokenAsset loan,uint256 loanRepayAmount,uint32 duration,uint40 expiration,address lender,bytes32 nonce)MultiTokenAsset(address assetAddress,uint8 category,uint256 amount,uint256 id)"
    );

    /**
     * EIP-712 multitoken asset struct type hash
     */
    bytes32 constant internal MULTITOKEN_ASSET_TYPEHASH = keccak256(
        "MultiTokenAsset(address assetAddress,uint8 category,uint256 amount,uint256 id)"
    );

    /**
     * Construct defining a Deed
     * @param status 0 == none/dead || 1 == new/open || 2 == running/accepted offer || 3 == paid back || 4 == expired
     * @param borrower Address of the borrower - stays the same for entire lifespan of the token
     * @param duration Loan duration in seconds
     * @param expiration Unix timestamp (in seconds) setting up the default deadline
     * @param collateral Asset used as a loan collateral. Consisting of another `Asset` struct defined in the MultiToken library
     * @param loan Asset to be borrowed by lender to borrower. Consisting of another `Asset` struct defined in the MultiToken library
     * @param loanRepayAmount Amount of loan asset to be repaid
     */
    struct Deed {
        uint8 status;
        address borrower;
        uint32 duration;
        uint40 expiration;
        MultiToken.Asset collateral;
        MultiToken.Asset loan;
        uint256 loanRepayAmount;
    }

    /**
     * Construct defining an Offer
     * @param collateral Asset used as a loan collateral
     * @param loan Asset to be borrowed by lender to borrower
     * @param loanRepayAmount Amount of loan asset to be repaid
     * @param duration Loan duration in seconds
     * @param expiration Offer expiration timestamp in seconds
     * @param lender Offer owner and provider of a loan asset
     * @param nonce Incremental nonce to help distinguish between otherwise identical offers
     */
    struct Offer {
        MultiToken.Asset collateral;
        MultiToken.Asset loan;
        uint256 loanRepayAmount;
        uint32 duration;
        uint40 expiration;
        address lender;
        bytes32 nonce;
    }

    /**
     * Mapping of all Deed data by deed id
     */
    mapping (uint256 => Deed) public deeds;

    /**
     * Mapping of revoked offers by offer struct typed hash
     */
    mapping (bytes32 => bool) public revokedOffers;

    /*----------------------------------------------------------*|
    |*  # EVENTS & ERRORS DEFINITIONS                           *|
    |*----------------------------------------------------------*/

    event DeedCreated(uint256 indexed did, address indexed lender, bytes32 indexed offerHash);
    event OfferRevoked(bytes32 indexed offerHash);
    event PaidBack(uint256 did);
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
     * PWN Deed constructor
     * @dev Creates the PWN Deed token contract - ERC1155 with extra use case specific features
     * @dev Once the PWN contract is set, you'll have to call `this.setPWN(PWN.address)` for this contract to work
     * @param _uri Uri to be used for finding the token metadata (https://api.pwn.finance/deed/...)
     */
    constructor(string memory _uri) ERC1155(_uri) Ownable() {

    }

    /**
     * All contracts of this section can only be called by the PWN contract itself - once set via `setPWN(PWN.address)`
     */

    /**
     * revokeOffer
     * @notice Revoke an offer
     * @dev Offer is revoked by lender or when offer is accepted by borrower to prevent accepting it twice
     * @param _offerHash Offer typed struct hash
     * @param _signature Offer typed struct signature
     * @param _sender Address of a message sender (lender)
     */
    function revokeOffer(
        bytes32 _offerHash,
        bytes calldata _signature,
        address _sender
    ) external onlyPWN {
        require(ECDSA.recover(_offerHash, _signature) == _sender, "Sender is not an offer signer");
        require(revokedOffers[_offerHash] == false, "Offer is already revoked or has been accepted");

        revokedOffers[_offerHash] = true;

        emit OfferRevoked(_offerHash);
    }

    /**
     * create
     * @notice Creates the PWN Deed token contract - ERC1155 with extra use case specific features
     * @dev Contract wallets need to implement EIP-1271 to validate signature on the contract behalf
     * @param _offer Offer struct holding plain offer data
     * @param _signature Offer typed struct signature signed by lender
     * @param _sender Address of a message sender (borrower)
     */
    function create(
        Offer memory _offer,
        bytes memory _signature,
        address _sender
    ) external onlyPWN {
        bytes32 eip712DomainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("PWN")),
            keccak256(bytes("1")),
            block.chainid,
            address(this)
        ));

        bytes32 offerHash = keccak256(abi.encodePacked(
            "\x19\x01", eip712DomainSeparator, hash(_offer)
        ));

        if (_offer.lender.code.length > 0) {
            require(IERC1271(_offer.lender).isValidSignature(offerHash, _signature) == EIP1271_VALID_SIGNATURE, "Signature on behalf of contract is invalid");
        } else {
            require(ECDSA.recover(offerHash, _signature) == _offer.lender, "Lender address didn't sign the offer");
        }
        require(_offer.expiration == 0 || block.timestamp < _offer.expiration, "Offer is expired");
        require(revokedOffers[offerHash] == false, "Offer is revoked or has been accepted");

        revokedOffers[offerHash] = true;

        id++;

        Deed storage deed = deeds[id];
        deed.status = 2;
        deed.borrower = _sender;
        deed.duration = _offer.duration;
        deed.expiration = uint40(block.timestamp) + _offer.duration;
        deed.collateral = _offer.collateral;
        deed.loan = _offer.loan;
        deed.loanRepayAmount = _offer.loanRepayAmount;

        _mint(_offer.lender, id, 1, "");

        emit DeedCreated(id, _offer.lender, offerHash);
    }

    /**
     * repayLoan
     * @notice Function to make proper state transition
     * @param _did ID of the Deed which is paid back
     */
    function repayLoan(uint256 _did) external onlyPWN {
        require(getStatus(_did) == 2, "Deed is not running and cannot be paid back");

        deeds[_did].status = 3;

        emit PaidBack(_did);
    }

    /**
     * claim
     * @notice Function that would set the deed to the dead state if the token is in paidBack or expired state
     * @param _did ID of the Deed which is claimed
     * @param _owner Address of the deed token owner
     */
    function claim(
        uint256 _did,
        address _owner
    ) external onlyPWN {
        require(balanceOf(_owner, _did) == 1, "Caller is not the deed owner");
        require(getStatus(_did) >= 3, "Deed can't be claimed yet");

        deeds[_did].status = 0;

        emit DeedClaimed(_did);
    }

    /**
     * burn
     * @notice Function that would burn the deed token if the token is in dead state
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

    /**
     * getStatus
     * @dev used in contract calls & status checks and also in UI for elementary deed status categorization
     * @param _did Deed ID checked for status
     * @return a status number
     */
    function getStatus(uint256 _did) public view returns (uint8) {
        if (deeds[_did].expiration > 0 && deeds[_did].expiration < block.timestamp && deeds[_did].status != 3) {
            return 4;
        } else {
            return deeds[_did].status;
        }
    }

    /**
     * getExpiration
     * @dev utility function to find out exact expiration time of a particular Deed
     * @dev for simple status check use `this.getStatus(did)` if `status == 4` then Deed has expired
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
     * getCollateral
     * @dev utility function to find out collateral asset of a particular Deed
     * @param _did Deed ID to be checked
     * @return Asset construct - for definition see { MultiToken.sol }
     */
    function getCollateral(uint256 _did) public view returns (MultiToken.Asset memory) {
        return deeds[_did].collateral;
    }

    /**
     * getLoan
     * @dev utility function to find out loan asset of a particular Deed
     * @param _did Deed ID to be checked
     * @return Asset construct - for definition see { MultiToken.sol }
     */
    function getLoan(uint256 _did) public view returns (MultiToken.Asset memory) {
        return deeds[_did].loan;
    }

    /**
     * getLoan
     * @dev utility function to find out loan repay amount of a particular Deed
     * @param _did Deed ID to be checked
     * @return Amount of loan asset to be repaid
     */
    function getLoanRepayAmount(uint256 _did) public view returns (uint256) {
        return deeds[_did].loanRepayAmount;
    }

    /**
     * isRevoked
     * @dev utility function to find out if offer is revoked
     * @param _offerHash Offer typed struct hash
     * @return True if offer is revoked
     */
    function isRevoked(bytes32 _offerHash) public view returns (bool) {
        return revokedOffers[_offerHash];
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

    /**
     * setUri
     * @dev An non-essential setup function. Can be called to adjust the Deed token metadata URI
     * @param _newUri setting the new origin of Deed metadata
     */
    function setUri(string memory _newUri) external onlyOwner {
        _setURI(_newUri);
    }

    /*--------------------------------*|
    |*  ## PRIVATE FUNCTIONS          *|
    |*--------------------------------*/

    /**
     * hash offer
     * @notice Hash offer struct according to EIP-712
     * @param _offer Offer struct to be hashed
     * @return Offer struct hash
     */
    function hash(Offer memory _offer) private pure returns (bytes32) {
        return keccak256(abi.encode(
            OFFER_TYPEHASH,
            hash(_offer.collateral),
            hash(_offer.loan),
            _offer.loanRepayAmount,
            _offer.duration,
            _offer.expiration,
            _offer.lender,
            _offer.nonce
        ));
    }

    /**
     * hash multitoken asset
     * @notice Hash MultiToken asset struct according to EIP-712
     * @param _asset MultiToken asset struct to be hashed
     * @return MultiToken asset struct hash
     */
    function hash(MultiToken.Asset memory _asset) private pure returns (bytes32) {
        return keccak256(abi.encode(
            MULTITOKEN_ASSET_TYPEHASH,
            _asset.assetAddress,
            _asset.category,
            _asset.amount,
            _asset.id
        ));
    }
}
