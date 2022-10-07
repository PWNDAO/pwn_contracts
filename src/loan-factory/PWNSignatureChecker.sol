// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC1271.sol";


library PWNSignatureChecker {

    string internal constant VERSION = "0.1.0";

    // TODO: Doc
    function isValidSignatureNow(
        address signer,
        bytes32 hash,
        bytes memory signature
    ) internal view returns (bool) {
        // Check that signature is valid for contract account
        if (signer.code.length > 0) {
            (bool success, bytes memory result) = signer.staticcall(
                abi.encodeWithSelector(IERC1271.isValidSignature.selector, hash, signature)
            );
            return
                success &&
                result.length == 32 &&
                abi.decode(result, (bytes32)) == bytes32(IERC1271.isValidSignature.selector);
        }
        // Check that signature is valid for EOA
        else {
            bytes32 r;
            bytes32 s;
            uint8 v;

            // Standard signature data (65 bytes)
            if (signature.length == 65) {
                assembly {
                    r := mload(add(signature, 0x20))
                    s := mload(add(signature, 0x40))
                    v := byte(0, mload(add(signature, 0x60)))
                }
            }
            // Compact signature data (64 bytes) - see EIP-2098
            else if (signature.length == 64) {
                bytes32 vs;

                assembly {
                    r := mload(add(signature, 0x20))
                    vs := mload(add(signature, 0x40))
                }

                s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
                v = uint8((uint256(vs) >> 255) + 27);
            } else {
                revert("PWNSignatureChecker: Invalid signature length");
            }

            return signer == ECDSA.recover(hash, v, r, s);
        }
    }

}
