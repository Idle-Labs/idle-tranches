// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./IdleCDO.sol";
import "./IdleCDOCards.sol";

contract IdleCDOCard {
  using SafeERC20Upgradeable for IERC20Detailed;
  using SafeMath for uint256;

  IdleCDOCards internal manager;

  modifier onlyOwner() {
    require(msg.sender == address(manager), "Ownable: card caller is not the card manager owner");
    _;
  }

  constructor() {
    manager = IdleCDOCards(msg.sender);
    require(keccak256(bytes(manager.name())) == keccak256(bytes("IdleCDOCards")), "creator is not an IdleCDOCards contract");
  }

  function mint(uint256 _amountAA, uint256 _amountBB) public onlyOwner returns (uint256) {
    IdleCDO idleCDO = manager.idleCDO();
    uint256 amount = _amountAA.add(_amountBB);

    // transfer amount to cards protocol
    manager.idleCDOToken().safeTransferFrom(address(manager), address(this), amount);

    // approve the amount to be spend on cdos tranches
    manager.idleCDOToken().approve(address(idleCDO), amount);

    // deposit the amount to the cdos tranches;
    idleCDO.depositAA(_amountAA);
    idleCDO.depositBB(_amountBB);

    return amount;
  }

  function burn() public onlyOwner returns (uint256 toRedeem) {
    (uint256 balanceAA, uint256 balanceBB) = balance();

    IdleCDO idleCDO = manager.idleCDO();
    uint256 toRedeemAA = balanceAA > 0 ? idleCDO.withdrawAA(0) : 0;
    uint256 toRedeemBB = balanceBB > 0 ? idleCDO.withdrawBB(0) : 0;

    // transfers everything withdrawn to the manager
    toRedeem = toRedeemAA.add(toRedeemBB);
    manager.idleCDOToken().safeTransfer(address(manager), toRedeem);
  }

  function balance() public view returns (uint256 balanceAA, uint256 balanceBB) {
    IdleCDO idleCDO = manager.idleCDO();

    balanceAA = IERC20Detailed(idleCDO.AATranche()).balanceOf(address(this));
    balanceBB = IERC20Detailed(idleCDO.BBTranche()).balanceOf(address(this));
  }
}
