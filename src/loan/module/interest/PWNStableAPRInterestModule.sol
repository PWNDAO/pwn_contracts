// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { Math } from "openzeppelin/utils/math/Math.sol";

import { PWNHub } from "pwn/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import { IPWNInterestModule, INTEREST_MODULE_INIT_HOOK_RETURN_VALUE } from "pwn/loan/module/interest/IPWNInterestModule.sol";
import { PWNLoan } from "pwn/loan/PWNLoan.sol";


contract PWNStableAPRInterestModule is IPWNInterestModule {
    using Math for uint256;

    uint256 public constant APR_DECIMALS = 4; // 6231 = 0.6231 = 62.31%

    error CallerNotActiveLoan();
    error InvalidLastUpdateTimestamp();

    PWNHub public immutable hub;

    struct ProposerData {
        uint256 apr;
    }

    mapping (address => mapping(uint256 => uint256)) public apr;


    constructor(PWNHub _hub) {
        hub = _hub;
    }


    function interest(address loanContract, uint256 loanId) external view returns (uint256) {
        PWNLoan.LOAN memory loan = PWNLoan(loanContract).getLOAN(loanId);

        if (block.timestamp < loan.lastUpdateTimestamp) revert InvalidLastUpdateTimestamp();

        uint256 accruingMinutes = (block.timestamp - loan.lastUpdateTimestamp) / 1 minutes;
        return loan.principal.mulDiv(apr[loanContract][loanId] * accruingMinutes, 10 ** APR_DECIMALS);
    }

    function onLoanCreated(uint256 loanId, bytes calldata proposerData) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();

        ProposerData memory proposer = abi.decode(proposerData, (ProposerData));
        apr[msg.sender][loanId] = proposer.apr;

        return INTEREST_MODULE_INIT_HOOK_RETURN_VALUE;
    }

}
