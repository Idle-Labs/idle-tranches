// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../IdleCDOCardManager.sol";

contract EvilIdleCdoCardManager is IdleCDOCardManager {
  using SafeERC20Upgradeable for IERC20Detailed;

  constructor(address[] memory _idleCDOAddress) IdleCDOCardManager(_idleCDOAddress) {}

  function evilMint(address cardAddress, uint256 amountAA, uint256 amountBB) public returns (uint256) {
    uint256 _amount = amountAA + amountBB;
    IdleCDOCard _card = IdleCDOCard(cardAddress);

    // transfer amount to cards protocol
    erc20().safeTransferFrom(msg.sender, address(this), _amount);

    // approve the amount to be spend on cdos tranches
    erc20().approve(address(_card), _amount);

    _card.mint(address(this),amountAA, amountBB);
    return _amount;
  }

  function evilBurn(address cardAddress) public returns (uint256 toRedeem) {
    IdleCDOCard _card = IdleCDOCard(cardAddress);
    return _card.burn(address(this));
  }

  function erc20() private view returns (IERC20Detailed) {
    return IERC20Detailed(this.idleCDOs(0).token());
  }
}
