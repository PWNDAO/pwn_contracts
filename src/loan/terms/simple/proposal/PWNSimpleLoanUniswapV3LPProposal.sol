// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { MultiToken } from "MultiToken/MultiToken.sol";

import { Math } from "openzeppelin/utils/math/Math.sol";

import {
    Chainlink,
    IChainlinkFeedRegistryLike,
    IChainlinkAggregatorLike
} from "pwn/loan/lib/Chainlink.sol";
import {
    UniswapV3,
    INonfungiblePositionManager
} from "pwn/loan/lib/UniswapV3.sol";
import { PWNSimpleLoan } from "pwn/loan/terms/simple/loan/PWNSimpleLoan.sol";
import { PWNSimpleLoanProposal } from "pwn/loan/terms/simple/proposal/PWNSimpleLoanProposal.sol";


/**
 * @title PWN Simple Loan Uniswap V3 LP Proposal
 * @notice Simple loan proposal contract for Uniswap V3 LP tokens.
 * Proposal uses Chainlink price feeds to get LP token value in credit token.
 */
contract PWNSimpleLoanUniswapV3LPProposal is PWNSimpleLoanProposal {
    using Math for uint256;
    using UniswapV3 for UniswapV3.Config;
    using Chainlink for Chainlink.Config;

    string public constant VERSION = "1.0";

    /** @notice Maximum number of intermediary denominations for price conversion.*/
    uint256 public constant MAX_INTERMEDIARY_DENOMINATIONS = 2;
    /** @notice Loan to value denominator.*/
    uint256 public constant LOAN_TO_VALUE_DENOMINATOR = 1e4;

    /** @notice Uniswap V3 factory contract.*/
    address public immutable uniswapV3Factory;
    /** @notice Uniswap V3 NFT position manager contract.*/
    INonfungiblePositionManager public immutable uniswapNFTPositionManager;
    /** @notice Chainlink feed registry contract.*/
    IChainlinkFeedRegistryLike public immutable chainlinkFeedRegistry;
    /** @notice Chainlink feed for L2 Sequencer uptime. Must be address(0) for L1s.*/
    IChainlinkAggregatorLike public immutable l2SequencerUptimeFeed;
    /** @notice WETH address. ETH price feed is used for WETH price.*/
    address public immutable WETH;

    /** @dev EIP-712 proposal type hash.*/
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256(
        "Proposal(address[] tokenAAllowlist,address[] tokenBAllowlist,address creditAddress,address[] feedIntermediaryDenominations,bool[] feedInvertFlags,uint256 loanToValue,uint256 minCreditAmount,uint256 availableCreditLimit,bytes32 utilizedCreditId,uint256 fixedInterestAmount,uint24 accruingInterestAPR,uint32 durationOrDate,uint40 expiration,address acceptorController,bytes acceptorControllerData,address proposer,bytes32 proposerSpecHash,bool isOffer,uint256 refinancingLoanId,uint256 nonceSpace,uint256 nonce,address loanContract)"
    );

    /**
     * @notice Construct defining a Uniswap LP proposal.
     * @param tokenAAllowlist List of tokenA addresses that are allowed in the LP token pair.
     * @param tokenBAllowlist List of tokenB addresses that are allowed in the LP token pair.
     * @param creditAddress Credit token address.
     * @param feedIntermediaryDenominations List of intermediary price assets that will be used to fetch prices to get to the correct asset denominator.
     * @param feedInvertFlags List of flags indicating if price feeds exist only for inverted base and quote assets.
     * @param loanToValue Loan to value ratio with 4 decimals. E.g., 6231 == 0.6231 == 62.31%.
     * @param minCreditAmount Minimum credit amount that can be requested.
     * @param availableCreditLimit Available credit limit for the proposal.
     * @param utilizedCreditId ID of the utilized credit.
     * @param fixedInterestAmount Fixed interest amount that will be paid with the credit.
     * @param accruingInterestAPR Accruing interest APR with 2 decimals. E.g., 6231 == 62.31 APR.
     * @param durationOrDate Duration in seconds or date when the loan will expire.
     * @param expiration Expiration timestamp of the proposal.
     * @param acceptorController Address of an acceptor controller contract. It is used to check if an address can accept the proposal.
     * @param acceptorControllerData Proposer data for an acceptor controller contract.
     * @param proposer Address of a proposal signer. If `isOffer` is true, the proposer is the lender. If `isOffer` is false, the proposer is the borrower.
     * @param proposerSpecHash Hash of a proposer specific data, which must be provided during a loan creation.
     * @param isOffer If true, the proposal is an offer. If false, the proposal is a request.
     * @param refinancingLoanId Id of a loan which is refinanced by this proposal. If the id is 0 and `isOffer` is true, the proposal can refinance any loan.
     * @param nonceSpace Nonce space of a proposal nonce. All nonces in the same space can be revoked at once.
     * @param nonce Additional value to enable identical proposals in time. Without it, it would be impossible to make again proposal, which was once revoked. Can be used to create a group of proposals, where accepting one will make others in the group invalid.
     * @param loanContract Address of a loan contract that will create a loan from the proposal.
     */
    struct Proposal {
        address[] tokenAAllowlist;
        address[] tokenBAllowlist;
        address creditAddress;
        address[] feedIntermediaryDenominations;
        bool[] feedInvertFlags;
        uint256 loanToValue;
        uint256 minCreditAmount;
        uint256 availableCreditLimit;
        bytes32 utilizedCreditId;
        uint256 fixedInterestAmount;
        uint24 accruingInterestAPR;
        uint32 durationOrDate;
        uint40 expiration;
        address acceptorController;
        bytes acceptorControllerData;
        address proposer;
        bytes32 proposerSpecHash;
        bool isOffer;
        uint256 refinancingLoanId;
        uint256 nonceSpace;
        uint256 nonce;
        address loanContract;
    }

    /**
     * @notice Construct defining proposal concrete values.
     * @param collateralId Uniswap LP token ID.
     * @param tokenAIndex Index of tokenA in tokenAAllowlist.
     * @param tokenBIndex Index of tokenB in tokenBAllowlist.
     * @param acceptorControllerData Acceptor data for an acceptor controller contract.
     */
    struct ProposalValues {
        uint256 collateralId;
        uint256 tokenAIndex;
        uint256 tokenBIndex;
        bytes acceptorControllerData;
    }

    /** @notice Emitted when a proposal is made via an on-chain transaction.*/
    event ProposalMade(bytes32 indexed proposalHash, address indexed proposer, Proposal proposal);

    /** @notice Thrown when proposal has no minimum credit amount set.*/
    error MinCreditAmountNotSet();
    /** @notice Thrown when proposal credit amount is insufficient.*/
    error InsufficientCreditAmount(uint256 current, uint256 limit);
    /** @notice Thrown when LP token pair is not part of the proposal.*/
    error InvalidLPTokenPair();


    constructor(
        address _hub,
        address _revokedNonce,
        address _config,
        address _utilizedCredit,
        address _uniswapV3Factory,
        address _uniswapNFTPositionManager,
        address _chainlinkFeedRegistry,
        address _l2SequencerUptimeFeed,
        address _weth
    ) PWNSimpleLoanProposal(_hub, _revokedNonce, _config, _utilizedCredit, "PWNSimpleLoanUniswapLPProposal", VERSION) {
        uniswapV3Factory = _uniswapV3Factory;
        uniswapNFTPositionManager = INonfungiblePositionManager(_uniswapNFTPositionManager);
        chainlinkFeedRegistry = IChainlinkFeedRegistryLike(_chainlinkFeedRegistry);
        l2SequencerUptimeFeed = IChainlinkAggregatorLike(_l2SequencerUptimeFeed);
        WETH = _weth;
    }

    /**
     * @notice Get an proposal hash according to EIP-712
     * @param proposal Proposal struct to be hashed.
     * @return Proposal struct hash.
     */
    function getProposalHash(Proposal calldata proposal) public view returns (bytes32) {
        return _getProposalHash(PROPOSAL_TYPEHASH, _erc712EncodeProposal(proposal));
    }

    /**
     * @notice Make an on-chain proposal.
     * @dev Function will mark a proposal hash as proposed.
     * @param proposal Proposal struct containing all needed proposal data.
     * @return proposalHash Proposal hash.
     */
    function makeProposal(Proposal calldata proposal) external returns (bytes32 proposalHash) {
        proposalHash = getProposalHash(proposal);
        _makeProposal(proposalHash, proposal.proposer);
        emit ProposalMade(proposalHash, proposal.proposer, proposal);
    }

    /**
     * @notice Encode proposal data.
     * @param proposal Proposal struct to be encoded.
     * @param proposalValues ProposalValues struct to be encoded.
     * @return Encoded proposal data.
     */
    function encodeProposalData(
        Proposal memory proposal,
        ProposalValues memory proposalValues
    ) external pure returns (bytes memory) {
        return abi.encode(proposal, proposalValues);
    }

    /**
     * @notice Decode proposal data.
     * @param proposalData Encoded proposal data.
     * @return Decoded proposal struct.
     * @return Decoded proposal values struct.
     */
    function decodeProposalData(bytes memory proposalData) public pure returns (Proposal memory, ProposalValues memory) {
        return abi.decode(proposalData, (Proposal, ProposalValues));
    }

    /**
     * @notice Get credit amount for a given LP token and loan to value.
     * @param creditAddress Credit token address.
     * @param collateralId LP token ID.
     * @param token0Denominator Flag indicating if token0 should be used as LP value denominator.
     * @param feedIntermediaryDenominations List of intermediary price assets that will be used to fetch prices to get to the correct asset denominator.
     * @param feedInvertFlags List of flags indicating if price feeds exist only for inverted base and quote assets.
     * @param loanToValue Loan to value ratio with 4 decimals. E.g., 6231 == 0.6231 == 62.31%.
     * @return Amount of credit.
     */
    function getCreditAmount(
        address creditAddress,
        uint256 collateralId,
        bool token0Denominator,
        address[] memory feedIntermediaryDenominations,
        bool[] memory feedInvertFlags,
        uint256 loanToValue
    ) public view returns (uint256) {
        (uint256 lpValue, address denominator) = uniswap().getLPValue({
            tokenId: collateralId,
            token0Denominator: token0Denominator
        });

        if (creditAddress != denominator) {
            lpValue = chainlink().convertDenomination({
                amount: lpValue,
                oldDenomination: denominator,
                newDenomination: creditAddress,
                feedIntermediaryDenominations: feedIntermediaryDenominations,
                feedInvertFlags: feedInvertFlags
            });
        }

        return lpValue.mulDiv(loanToValue, LOAN_TO_VALUE_DENOMINATOR);
    }

    /** @inheritdoc PWNSimpleLoanProposal*/
    function acceptProposal(
        address acceptor,
        uint256 refinancingLoanId,
        bytes calldata proposalData,
        bytes32[] calldata proposalInclusionProof,
        bytes calldata signature
    ) override external returns (bytes32 proposalHash, PWNSimpleLoan.Terms memory loanTerms) {
        // Decode proposal data
        (Proposal memory proposal, ProposalValues memory proposalValues) = decodeProposalData(proposalData);

        // Make proposal hash
        proposalHash = _getProposalHash(PROPOSAL_TYPEHASH, _erc712EncodeProposal(proposal));

        // Check min credit amount
        if (proposal.minCreditAmount == 0) {
            revert MinCreditAmountNotSet();
        }

        bool token0Denominator = _checkLPTokenPair(proposal, proposalValues);
        // Fill loan terms object
        loanTerms = PWNSimpleLoan.Terms({
            lender: proposal.isOffer ? proposal.proposer : acceptor,
            borrower: proposal.isOffer ? acceptor : proposal.proposer,
            duration: _getLoanDuration(proposal.durationOrDate),
            collateral: MultiToken.ERC721({
                assetAddress: address(uniswapNFTPositionManager),
                id: proposalValues.collateralId
            }),
            credit: MultiToken.ERC20({
                assetAddress: proposal.creditAddress,
                amount: getCreditAmount(
                    proposal.creditAddress,
                    proposalValues.collateralId,
                    token0Denominator,
                    proposal.feedIntermediaryDenominations,
                    proposal.feedInvertFlags,
                    proposal.loanToValue
                )
            }),
            fixedInterestAmount: proposal.fixedInterestAmount,
            accruingInterestAPR: proposal.accruingInterestAPR,
            lenderSpecHash: proposal.isOffer ? proposal.proposerSpecHash : bytes32(0),
            borrowerSpecHash: proposal.isOffer ? bytes32(0) : proposal.proposerSpecHash
        });

        // Check sufficient credit amount
        if (loanTerms.credit.amount < proposal.minCreditAmount) {
            revert InsufficientCreditAmount({ current: loanTerms.credit.amount, limit: proposal.minCreditAmount });
        }

        ProposalValuesBase memory proposalValuesBase = ProposalValuesBase({
            refinancingLoanId: refinancingLoanId,
            acceptor: acceptor,
            acceptorControllerData: proposalValues.acceptorControllerData
        });

        // Try to accept proposal
        _acceptProposal(
            proposalHash,
            proposalInclusionProof,
            signature,
            ProposalBase({
                collateralAddress: address(uniswapNFTPositionManager),
                collateralId: proposalValues.collateralId,
                checkCollateralStateFingerprint: false,
                collateralStateFingerprint: bytes32(0),
                creditAmount: loanTerms.credit.amount,
                availableCreditLimit: proposal.availableCreditLimit,
                utilizedCreditId: proposal.utilizedCreditId,
                expiration: proposal.expiration,
                acceptorController: proposal.acceptorController,
                acceptorControllerData: proposal.acceptorControllerData,
                proposer: proposal.proposer,
                isOffer: proposal.isOffer,
                refinancingLoanId: proposal.refinancingLoanId,
                nonceSpace: proposal.nonceSpace,
                nonce: proposal.nonce,
                loanContract: proposal.loanContract
            }),
            proposalValuesBase
        );
    }

    /** @dev Returns if token0 should be used as LP denominator.*/
    function _checkLPTokenPair(Proposal memory proposal, ProposalValues memory proposalValues) internal view returns (bool) {
        (,,address token0, address token1,,,,,,,,) = uniswapNFTPositionManager.positions(proposalValues.collateralId);
        address tokenA = proposal.tokenAAllowlist[proposalValues.tokenAIndex];
        address tokenB = proposal.tokenBAllowlist[proposalValues.tokenBIndex];
        if (token0 == tokenA) {
            if (token1 != tokenB) {
                revert InvalidLPTokenPair();
            }
        } else if (token1 == tokenA) {
            if (token0 != tokenB) {
                revert InvalidLPTokenPair();
            }
        } else {
            revert InvalidLPTokenPair();
        }

        return token0 == tokenA;
    }

    /** @notice Proposal struct that is typecasting dynamic values to bytes32 to enable easy EIP-712 encoding.*/
    struct ERC712Proposal {
        bytes32 tokenAAllowlistHash;
        bytes32 tokenBAllowlistHash;
        address creditAddress;
        bytes32 feedIntermediaryDenominationsHash;
        bytes32 feedInvertFlagsHash;
        uint256 loanToValue;
        uint256 minCreditAmount;
        uint256 availableCreditLimit;
        bytes32 utilizedCreditId;
        uint256 fixedInterestAmount;
        uint24 accruingInterestAPR;
        uint32 durationOrDate;
        uint40 expiration;
        address acceptorController;
        bytes32 acceptorControllerDataHash;
        address proposer;
        bytes32 proposerSpecHash;
        bool isOffer;
        uint256 refinancingLoanId;
        uint256 nonceSpace;
        uint256 nonce;
        address loanContract;
    }

    function _erc712EncodeProposal(Proposal memory proposal) internal pure returns (bytes memory) {
        ERC712Proposal memory erc712Proposal = ERC712Proposal({
            tokenAAllowlistHash: keccak256(abi.encodePacked(proposal.tokenAAllowlist)),
            tokenBAllowlistHash: keccak256(abi.encodePacked(proposal.tokenBAllowlist)),
            creditAddress: proposal.creditAddress,
            feedIntermediaryDenominationsHash: keccak256(abi.encodePacked(proposal.feedIntermediaryDenominations)),
            feedInvertFlagsHash: keccak256(abi.encodePacked(proposal.feedInvertFlags)),
            loanToValue: proposal.loanToValue,
            minCreditAmount: proposal.minCreditAmount,
            availableCreditLimit: proposal.availableCreditLimit,
            utilizedCreditId: proposal.utilizedCreditId,
            fixedInterestAmount: proposal.fixedInterestAmount,
            accruingInterestAPR: proposal.accruingInterestAPR,
            durationOrDate: proposal.durationOrDate,
            expiration: proposal.expiration,
            acceptorController: proposal.acceptorController,
            acceptorControllerDataHash: keccak256(proposal.acceptorControllerData),
            proposer: proposal.proposer,
            proposerSpecHash: proposal.proposerSpecHash,
            isOffer: proposal.isOffer,
            refinancingLoanId: proposal.refinancingLoanId,
            nonceSpace: proposal.nonceSpace,
            nonce: proposal.nonce,
            loanContract: proposal.loanContract
        });
        return abi.encode(erc712Proposal);
    }

    function uniswap() internal view returns (UniswapV3.Config memory) {
        return UniswapV3.Config({
            uniswapNFTPositionManager: uniswapNFTPositionManager,
            uniswapV3Factory: uniswapV3Factory
        });
    }

    function chainlink() internal view returns (Chainlink.Config memory) {
        return Chainlink.Config({
            l2SequencerUptimeFeed: l2SequencerUptimeFeed,
            chainlinkFeedRegistry: chainlinkFeedRegistry,
            maxIntermediaryDenominations: MAX_INTERMEDIARY_DENOMINATIONS,
            weth: WETH
        });
    }

}
