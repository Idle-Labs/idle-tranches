// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./IdleCDO.sol";
import "./IdleCDOCard.sol";
import "./ERC721SimpleComposite.sol";

contract IdleCDOCardManager is ERC721SimpleComposite {
  using Counters for Counters.Counter;
  using SafeERC20Upgradeable for IERC20Detailed;
  using SafeMath for uint256;

  uint256 public constant RATIO_PRECISION = 10**18;

  struct Card {
    uint256 exposure;
    uint256 amount;
    address cardAddress;
    address idleCDOAddress;
  }

  IdleCDO[] public idleCDOs;

  Counters.Counter private _tokenIds;
  mapping(uint256 => Card) private _cards;

  constructor(address[] memory _idleCDOAddress) ERC721("IdleCDOCardManager", "ICC") {
    for (uint256 i = 0; i < _idleCDOAddress.length; i++) {
      idleCDOs.push(IdleCDO(_idleCDOAddress[i]));
    }
  }

  function getIdleCDOs() public view returns (IdleCDO[] memory) {
    return idleCDOs;
  }

  function mint(address _idleCDOAddress, uint256 _risk, uint256 _amount) public returns (uint256) {
    // check if _idleCDOAddress exists in idleCDOAddress array
    require(isIdleCDOListed(_idleCDOAddress), "IdleCDO address is not listed in the contract");

    IdleCDOCard _card = new IdleCDOCard(_idleCDOAddress);
    IERC20Detailed underlying = IERC20Detailed(IdleCDO(_idleCDOAddress).token());

    // transfer amount to cards protocol
    underlying.safeTransferFrom(msg.sender, address(this), _amount);

    // approve the amount to be spend on cdos tranches
    underlying.approve(address(_card), _amount);

    // calculate the amount to deposit in BB
    // proportional to risk
    uint256 depositBB = percentage(_risk, _amount);

    // calculate the amount to deposit in AA
    // inversely proportional to risk
    uint256 depositAA = _amount.sub(depositBB);

    _card.mint(depositAA, depositBB);

    // mint the Idle CDO card
    uint256 tokenId = _mint();
    _cards[tokenId] = Card(_risk, _amount, address(_card), _idleCDOAddress);

    return tokenId;
  }

  function mint(address _idleCDODAIAddress, uint256 _riskDAI, uint256 _amountDAI, address _idleCDOFEIAddress, uint256 _riskFEI, uint256 _amountFEI) public returns (uint256) {
    require(_amountDAI > 0 || _amountFEI > 0, "Not possible to mint a card with 0 amounts");
    
    if (_amountDAI == 0) {
      return mint(_idleCDOFEIAddress, _riskFEI, _amountFEI);
    }

    if (_amountFEI == 0) {
      return mint(_idleCDODAIAddress, _riskDAI, _amountDAI);
    }

    uint256 cardDAI = mint(_idleCDODAIAddress, _riskDAI, _amountDAI);
    uint256 cardFEI = mint(_idleCDOFEIAddress, _riskFEI, _amountFEI);

    return _combine(cardDAI, cardFEI);
  }

  function burn(uint256 _tokenId) public {
    require(!isNotExist(_tokenId), "Cannot burn an non existing token");
    
    if (_isLeaf(_tokenId)) {
      internalBurn(_tokenId);
      return;
    }
    
    (uint256 id0, uint256 id1) = _uncombine(_tokenId);
    internalBurn(id0);
    internalBurn(id1);
    return;
  }

  function card(uint256 _tokenId) public view returns (Card memory) {
    return _cards[_tokenId];
  }

  function getApr(address _idleCDOAddress, uint256 _exposure) public view returns (uint256) {
    IdleCDO idleCDO = IdleCDO(_idleCDOAddress);

    // ratioAA = ratio of 1 - _exposure of the AA apr
    uint256 aprAA = idleCDO.getApr(idleCDO.AATranche());
    uint256 ratioAA = percentage(RATIO_PRECISION.sub(_exposure), aprAA);

    // ratioBB = ratio of _exposure of the BB apr
    uint256 aprBB = idleCDO.getApr(idleCDO.BBTranche());
    uint256 ratioBB = percentage(_exposure, aprBB);

    return ratioAA.add(ratioBB);
  }

  function balance(uint256 _tokenId) public view returns (uint256 balanceAA, uint256 balanceBB) {
    require(!isNotExist(_tokenId), "inexistent card");
    require(_isLeaf(_tokenId), "Cannot get balance of a non leaf token");
    Card memory pos = card(_tokenId);
    IdleCDOCard _card = IdleCDOCard(pos.cardAddress);
    return _card.balance();
  }

  function percentage(uint256 _percentage, uint256 _amount) private pure returns (uint256) {
    require(_percentage < RATIO_PRECISION.add(1), "percentage should be between 0 and 1");
    return _amount.mul(_percentage).div(RATIO_PRECISION);
  }

  function _mint() internal override returns (uint256) {
    _tokenIds.increment();

    uint256 newItemId = _tokenIds.current();
    _mint(msg.sender, newItemId);

    return newItemId;
  }

  function internalBurn(uint256 _tokenId) internal returns (uint256 toRedeem) {
    require(msg.sender == ownerOf(_tokenId), "burn of risk card that is not own");

    _burn(_tokenId);

    Card memory pos = card(_tokenId);
    IdleCDOCard _card = IdleCDOCard(pos.cardAddress);
    toRedeem = _card.burn();

    // transfer to card owner
    IERC20Detailed underlying = IERC20Detailed(IdleCDO(pos.idleCDOAddress).token());
    underlying.safeTransfer(msg.sender, toRedeem);
  }

  function _isLeafExists(uint256 _tokenId) internal view virtual override returns (bool) {
    return _cards[_tokenId].cardAddress != address(0);
  }

  function isIdleCDOListed(address _idleCDOAddress) private view returns (bool) {
    for (uint256 i = 0; i < idleCDOs.length; i++) {
      if (address(idleCDOs[i]) == _idleCDOAddress) {
        return true;
      }
    }
    return false;
  }
}
