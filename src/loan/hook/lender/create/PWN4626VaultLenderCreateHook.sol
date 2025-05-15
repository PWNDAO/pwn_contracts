// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

import { PWNHub } from "pwn/hub/PWNHub.sol";
import { PWNHubTags } from "pwn/hub/PWNHubTags.sol";
import { IERC4626Like } from "pwn/interfaces/IERC4626Like.sol";
import { IPWNLenderCreateHook, LENDER_CREATE_HOOK_RETURN_VALUE } from "pwn/loan/hook/lender/create/IPWNLenderCreateHook.sol";


contract PWN4626VaultLenderCreateHook is IPWNLenderCreateHook {

    PWNHub public immutable hub;

    struct HookData {
        address vault;
    }

    error CallerNotActiveLoan();
    error LenderZeroAddress();
    error CreditZeroAddress();
    error PrincipalZero();
    error InvalidVaultAsset(address creditAsset, address vaultAsset);


    constructor(PWNHub _hub) {
        hub = _hub;
    }


    function onLoanCreated(
        address lender,
        address creditAddress,
        uint256 principal,
        bytes calldata lenderData
    ) external returns (bytes32) {
        if (!hub.hasTag(msg.sender, PWNHubTags.ACTIVE_LOAN)) revert CallerNotActiveLoan();

        if (lender == address(0)) revert LenderZeroAddress();
        if (creditAddress == address(0)) revert CreditZeroAddress();
        if (principal == 0) revert PrincipalZero();
        HookData memory data = abi.decode(lenderData, (HookData));

        // Check the asset of the vault
        address vaultAsset = IERC4626Like(data.vault).asset();
        if (creditAddress != vaultAsset) {
            revert InvalidVaultAsset(creditAddress, vaultAsset);
        }

        // Note: Performing optimistic withdraw, assuming that the vault will revert if the amount is not available
        // Withdraw from the vault to the owner
        IERC4626Like(data.vault).withdraw(principal, lender, lender);

        return LENDER_CREATE_HOOK_RETURN_VALUE;
    }

}
