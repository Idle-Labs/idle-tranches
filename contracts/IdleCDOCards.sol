// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./IdleCDO.sol";

contract IdleCDOCards is ERC721Enumerable {
  using Counters for Counters.Counter;
  using SafeERC20Upgradeable for IERC20Detailed;
  using SafeMath for uint256;

  uint256 public constant RATIO_PRECISION = 10**18;

  struct Card {
    uint256 exposure;
    uint256 amount;
    address cardAddress;
  }

  IdleCDO public idleCDO;
  Counters.Counter private _tokenIds;
  mapping(uint256 => Card) private _cards;

  constructor(address _idleCDOAddress) ERC721("IdleCDOCards", "ICC") {
    idleCDO = IdleCDO(_idleCDOAddress);
  }

  function mint(uint256 _risk, uint256 _amount) public returns (uint256) {
    IdleCDOCard _card = new IdleCDOCard();

    // transfer amount to cards protocol
    idleCDOToken().safeTransferFrom(msg.sender, address(this), _amount);

    // approve the amount to be spend on cdos tranches
    idleCDOToken().approve(address(_card), _amount);

    // calculate the amount to deposit in BB
    // proportional to risk
    uint256 depositBB = percentage(_risk, _amount);

    // calculate the amount to deposit in AA
    // inversely proportional to risk
    uint256 depositAA = _amount.sub(depositBB);

    _card.mint(depositAA, depositBB);

    // mint the Idle CDO card
    uint256 tokenId = _mint();
    _cards[tokenId] = Card(_risk, _amount, address(_card));

    return tokenId;
  }

  function card(uint256 _tokenId) public view returns (Card memory) {
    return _cards[_tokenId];
  }

  function burn(uint256 _tokenId) public returns (uint256 toRedeem) {
    require(msg.sender == ownerOf(_tokenId), "burn of risk card that is not own");

    _burn(_tokenId);

    Card memory pos = card(_tokenId);
    IdleCDOCard _card = IdleCDOCard(pos.cardAddress);
    uint256 toRedeem = _card.burn();

    // transfer to card owner
    idleCDOToken().safeTransfer(msg.sender, toRedeem);
  }

  function getApr(uint256 _exposure) public view returns (uint256) {
    // ratioAA = ratio of 1 - _exposure of the AA apr
    uint256 aprAA = idleCDO.getApr(idleCDO.AATranche());
    uint256 ratioAA = percentage(RATIO_PRECISION.sub(_exposure), aprAA);

    // ratioAA = ratio of _exposure of the AA apr
    uint256 aprBB = idleCDO.getApr(idleCDO.BBTranche());
    uint256 ratioBB = percentage(_exposure, aprBB);

    return ratioAA.add(ratioBB);
  }

  function balance(uint256 _tokenId) public view returns (uint256 balanceAA, uint256 balanceBB) {
    Card memory pos = card(_tokenId);
    require(pos.cardAddress != address(0), "inexistent card");
    IdleCDOCard _card = IdleCDOCard(pos.cardAddress);
    return _card.balance();
  }

  function percentage(uint256 _percentage, uint256 _amount) private pure returns (uint256) {
    require(_percentage < RATIO_PRECISION.add(1), "percentage should be between 0 and 1");
    return _amount.mul(_percentage).div(RATIO_PRECISION);
  }

  function _mint() private returns (uint256) {
    _tokenIds.increment();

    uint256 newItemId = _tokenIds.current();
    _mint(msg.sender, newItemId);

    return newItemId;
  }

  function idleCDOToken() public view returns (IERC20Detailed) {
    return IERC20Detailed(idleCDO.token());
  }
}

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
