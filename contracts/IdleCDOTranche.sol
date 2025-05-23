// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev ERC20 representing a tranche token
contract IdleCDOTranche is ERC20 {
  // allowed minter address
  address public minter;
  // liquidity burned at first tranche deposit
  uint256 internal constant MIN_LIQUIDITY = 10**3;

  /// @param _name tranche name
  /// @param _symbol tranche symbol
  constructor(
    string memory _name, // eg. IdleDAI
    string memory _symbol // eg. IDLEDAI
  ) ERC20(_name, _symbol) {
    // minter is msg.sender which is IdleCDO (in initialize)
    minter = msg.sender;
  }

  /// @param account that should receive the tranche tokens
  /// @param amount of tranche tokens to mint
  function mint(address account, uint256 amount) external {
    require(msg.sender == minter, '6');
    // burn MIN_LIQUIDITY on first tranche deposit
    if (totalSupply() == 0) {
      _mint(address(1), MIN_LIQUIDITY);
      amount -= MIN_LIQUIDITY;
    }
    _mint(account, amount);
  }

  /// @param account that should have the tranche tokens burned
  /// @param amount of tranche tokens to burn
  function burn(address account, uint256 amount) external {
    require(msg.sender == minter, '6');
    _burn(account, amount);
  }
}
