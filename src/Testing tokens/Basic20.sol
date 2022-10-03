// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

/**
 * @dev this is just a dummy mintable/burnable ERC20 for testing purposes
 */
contract Basic20 is ERC20, Ownable {
    
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    mapping(address => uint256) private _permitNonces;

    constructor(string memory name, string memory symbol)
        ERC20(name, symbol)
        Ownable()
    { }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "Expired");

        bytes memory data = abi.encode(
            PERMIT_TYPEHASH,
            owner,
            spender,
            value,
            _permitNonces[owner]++,
            deadline
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01", _eip712DomainSeparator(), keccak256(data)
            )
        );

        require(ECDSA.recover(digest, v, r, s) == owner, "EIP2612: invalid signature");

        _approve(owner, spender, value);
    }

    function nonces(address owner) external view returns (uint256) {
        return _permitNonces[owner];
    }

    function _eip712DomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("Basic20")),
            keccak256(bytes("1")),
            block.chainid,
            address(this)
        ));
    }
}
