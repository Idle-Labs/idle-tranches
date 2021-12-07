// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./IdleCDO.sol";
import "./IdleCDOCardManager.sol";

contract IdleCDOCard {
  using SafeERC20Upgradeable for IERC20Detailed;
  using SafeMath for uint256;

  IdleCDOCardManager internal manager;
  IdleCDO internal idleCDO;
  IERC20Detailed internal underlying;

  modifier onlyOwner() {
    require(msg.sender == address(manager), "Ownable: card caller is not the card manager owner");
    _;
  }

  constructor(address _idleCDOAddress) {
    manager = IdleCDOCardManager(msg.sender);
    require(keccak256(bytes(manager.name())) == keccak256(bytes("IdleCDOCardManager")), "creator is not an IdleCDOCardManager contract");
    idleCDO = IdleCDO(_idleCDOAddress);
    underlying = IERC20Detailed(idleCDO.token());
  }

  function mint(uint256 _amountAA, uint256 _amountBB) public onlyOwner returns (uint256) {
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

  function burn() public onlyOwner returns (uint256 toRedeem) {
    (uint256 balanceAA, uint256 balanceBB) = balance();

    uint256 toRedeemAA = balanceAA > 0 ? idleCDO.withdrawAA(0) : 0;
    uint256 toRedeemBB = balanceBB > 0 ? idleCDO.withdrawBB(0) : 0;

    // transfers everything withdrawn to the manager
    toRedeem = toRedeemAA.add(toRedeemBB);
    underlying.safeTransfer(address(manager), toRedeem);
  }

  function balance() public view returns (uint256 balanceAA, uint256 balanceBB) {
    balanceAA = IERC20Detailed(idleCDO.AATranche()).balanceOf(address(this));
    balanceBB = IERC20Detailed(idleCDO.BBTranche()).balanceOf(address(this));
  }
}
