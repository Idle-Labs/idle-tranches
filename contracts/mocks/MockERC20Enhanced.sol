// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract MockERC20Enhanced is ERC20Upgradeable {
  function initialize(
    string memory _name,
    string memory _symbol
  ) public {
    __ERC20_init(_name, _symbol);
    _mint(msg.sender, 10000000 * 10**18); // 10M to creator
  }
}
