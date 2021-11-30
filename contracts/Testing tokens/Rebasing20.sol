// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Rebasing20 is IERC20 {
	mapping(address => uint256) private _balances;

	mapping(address => mapping(address => uint256)) private _allowances;

	uint256 private _totalSupply;
	uint256 private _ratio = 10_000;


	constructor() public {

	}


	function totalSupply() override external view returns (uint256) {
		return _totalSupply / _ratio;
	}

	function balanceOf(address account) override external view returns (uint256) {
		return _balances[account] / _ratio;
	}

	function transfer(address recipient, uint256 amount) override external returns (bool) {
		require(recipient != address(0), "ERC20: transfer to the zero address");

		uint256 _amount = amount * _ratio;
		require(_balances[msg.sender] >= _amount, "ERC20: transfer amount exceeds balance");

		_balances[msg.sender] = _balances[msg.sender] - _amount;
		_balances[recipient] = _balances[recipient] + _amount;

		emit Transfer(msg.sender, recipient, amount);
		return true;
	}

	function transferFrom(address sender, address recipient, uint256 amount) override external returns (bool) {
		require(sender != address(0), "ERC20: transfer from the zero address");
		require(recipient != address(0), "ERC20: transfer to the zero address");

		uint256 _amount = amount * _ratio;
		require(_balances[sender] >= _amount, "ERC20: transfer amount exceeds balance");
		require(_allowances[sender][msg.sender] >= amount, "ERC20: transfer amount exceeds allowance");

		_balances[sender] = _balances[sender] - _amount;
		_balances[recipient] = _balances[recipient] + _amount;

		emit Transfer(sender, recipient, amount);
		return true;
	}

	function allowance(address owner, address spender) override external view returns (uint256) {
		return _allowances[owner][spender];
	}

	function approve(address spender, uint256 amount) override external returns (bool) {
		_allowances[msg.sender][spender] = amount;

		emit Approval(msg.sender, spender, amount);
		return true;
	}


	function mint(address account, uint256 amount) external virtual {
		require(account != address(0), "ERC20: mint to the zero address");

		_totalSupply += amount * _ratio;
		_balances[account] += amount * _ratio;
		emit Transfer(address(0), account, amount);
	}

	function burn(address account, uint256 amount) external virtual {
		require(account != address(0), "ERC20: burn from the zero address");

		uint256 accountBalance = _balances[account];
		require(accountBalance >= amount / _ratio, "ERC20: burn amount exceeds balance");
		unchecked {
			_balances[account] = accountBalance - amount / _ratio;
		}
		_totalSupply -= amount / _ratio;

		emit Transfer(account, address(0), amount);
	}


	function rebase(uint256 ratio) external {
		_ratio = ratio;
	}

}
