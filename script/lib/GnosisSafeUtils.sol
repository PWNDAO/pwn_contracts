// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.16;

interface GnosisSafeLike {
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);
}


library GnosisSafeUtils {

    function execTransaction(GnosisSafeLike safe, address to, bytes memory data) internal returns (bool) {
        uint256 ownerValue = uint256(uint160(msg.sender));
        return safe.execTransaction({
            to: to,
            value: 0,
            data: data,
            operation: 0,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: payable(0),
            signatures: abi.encodePacked(ownerValue, bytes32(0), uint8(1))
        });
    }

}
