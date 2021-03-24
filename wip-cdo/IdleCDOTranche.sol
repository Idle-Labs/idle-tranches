// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract IdleCDOTranche is ERC20 {
  address public minter;

  constructor(
    string memory _name, // eg. IdleDAI
    string memory _symbol // eg. IDLEDAI
  ) ERC20(_name, _symbol) {
    minter = msg.sender;
  }

  function mint(address account, uint256 amount) external {
    require(msg.sender == minter, 'TRANCHE:!AUTH');
    _mint(account, amount);
  }
  function burn(address account, uint256 amount) external {
    require(msg.sender == minter, 'TRANCHE:!AUTH');
    _burn(account, amount);
  }
}
