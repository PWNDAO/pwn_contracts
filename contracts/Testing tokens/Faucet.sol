pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Basic20.sol";
import "./Basic721.sol";
import "./Basic1155.sol";

contract Faucet is Ownable{
    uint256 nonce;
    Basic20 public ERC20a;
    Basic20 public ERC20b;
    Basic20 public ERC20c;
    Basic721 public ERC721a;
    Basic721 public ERC721b;
    Basic721 public ERC721c;
    Basic1155 public ERC1155a;
    Basic1155 public ERC1155b;

    constructor(address a, address b, address c, address d, address e, address f, address g, address h)
    Ownable()
    {
        ERC20a = Basic20(a);
        ERC20b = Basic20(b);
        ERC20c = Basic20(c);
        ERC721a = Basic721(d);
        ERC721b = Basic721(e);
        ERC721c = Basic721(f);
        ERC1155a = Basic1155(g);
        ERC1155b = Basic1155(h);
    }

    function gimme(address _address) external {
        nonce++;
        ERC20a.mint(_address, 1000000000000000000);
        ERC20b.mint(_address, 1000000000000000000);
        ERC20c.mint(_address, 1000000000000000000);
        ERC721a.mint(_address, nonce);
        ERC721b.mint(_address, nonce);
        ERC721c.mint(_address, nonce);
        ERC1155a.mint(_address, nonce, 1, ""); // ERC1155 NFT
        ERC1155a.mint(_address, 0, 1, ""); // ERC1155 fungible token
        ERC1155b.mint(_address, nonce, 1, ""); // ERC1155 NFT
    }

    function changeAddress(uint8 _token, address _target) external onlyOwner {
        if (_token == 0) {
            ERC20a = Basic20(_target);
        } else if (_token == 1) {
            ERC20b = Basic20(_target);
        } else if (_token == 2) {
            ERC20c = Basic20(_target);
        } else if (_token == 3) {
            ERC721a = Basic721(_target);
        } else if (_token == 4) {
            ERC721b = Basic721(_target);
        } else if (_token == 5) {
            ERC721c = Basic721(_target);
        } else if (_token == 6) {
            ERC1155a = Basic1155(_target);
        } else if (_token == 7) {
            ERC1155b = Basic1155(_target);
        }
    }

    function mintSpecific(uint8 _token, address _beneficiary, uint256 _amount, uint256 _id) external onlyOwner {
        if (_token == 0) {
            ERC20a.mint(_beneficiary, _amount);
        } else if (_token == 1) {
            ERC20b.mint(_beneficiary, _amount);
        } else if (_token == 2) {
            ERC20c.mint(_beneficiary, _amount);
        } else if (_token == 3) {
            ERC721a.mint(_beneficiary, _id);
        } else if (_token == 4) {
            ERC721b.mint(_beneficiary, _id);
        } else if (_token == 5) {
            ERC721c.mint(_beneficiary, _id);
        } else if (_token == 6) {
            ERC1155a.mint(_beneficiary, _id, _amount, "");
        } else if (_token == 7) {
            ERC1155b.mint(_beneficiary, _id, _amount, "");
        }
    }
}
