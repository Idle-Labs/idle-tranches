// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./IdleCDO.sol";
import "./IdleCDOCardManager.sol";

contract IdleCDOCard {
  using SafeERC20Upgradeable for IERC20Detailed;
  using SafeMath for uint256;

  IdleCDOCardManager internal manager;

  modifier onlyOwner() {
    require(msg.sender == address(manager), "not the card manager owner");
    _;
  }

  constructor() {
    manager = IdleCDOCardManager(msg.sender);
    require(keccak256(bytes(manager.name())) == keccak256(bytes("IdleCDOCardManager")), "not an IdleCDOCardManager");
  }

  function mint(address _idleCDOAddress, uint256 _amountAA, uint256 _amountBB) external onlyOwner returns (uint256) {

    IdleCDO idleCDO = IdleCDO(_idleCDOAddress);
    IERC20Detailed underlying = IERC20Detailed(idleCDO.token());

    uint256 amount = _amountAA.add(_amountBB);

    // transfer amount to cards protocol
    underlying.safeTransferFrom(address(manager), address(this), amount);

    // approve the amount to be spend on cdos tranches
    underlying.approve(address(idleCDO), amount);

    // deposit the amount to the cdos tranches;
    idleCDO.depositAA(_amountAA);
    idleCDO.depositBB(_amountBB);

    return amount;
  }

  function burn(address _idleCDOAddress) external onlyOwner returns (uint256 toRedeem) {
    IdleCDO idleCDO = IdleCDO(_idleCDOAddress);
    IERC20Detailed underlying = IERC20Detailed(idleCDO.token());

    (uint256 balanceAA, uint256 balanceBB) = balance(_idleCDOAddress);

    uint256 toRedeemAA = balanceAA > 0 ? idleCDO.withdrawAA(0) : 0;
    uint256 toRedeemBB = balanceBB > 0 ? idleCDO.withdrawBB(0) : 0;

    // transfers everything withdrawn to the manager
    toRedeem = toRedeemAA.add(toRedeemBB);
    underlying.safeTransfer(address(manager), toRedeem);
  }

  // This function allows you to clean up / delete contract
  function destroy() public onlyOwner {
      selfdestruct(payable(address(manager)));
  }

  function balance(address _idleCDOAddress) public view returns (uint256 balanceAA, uint256 balanceBB) {
    IdleCDO idleCDO = IdleCDO(_idleCDOAddress);

    balanceAA = IERC20Detailed(idleCDO.AATranche()).balanceOf(address(this));
    balanceBB = IERC20Detailed(idleCDO.BBTranche()).balanceOf(address(this));
  }
}
