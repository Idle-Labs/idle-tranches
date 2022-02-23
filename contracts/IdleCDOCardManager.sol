// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./IdleCDO.sol";
import "./IdleCDOCard.sol";

contract IdleCDOCardManager is ERC721Enumerable {
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
  
  Card[] private _cardSet;
  mapping(uint256 => uint256[]) private _cards;

  constructor(address[] memory _idleCDOAddress) ERC721("IdleCDOCardManager", "ICC") {
    for (uint256 i = 0; i < _idleCDOAddress.length; i++) {
      idleCDOs.push(IdleCDO(_idleCDOAddress[i]));
    }
  }

  function getIdleCDOs() public view returns (IdleCDO[] memory) {
    return idleCDOs;
  }

  function mint(address _idleCDOPos1Address, uint256 _riskPos1, uint256 _amountPos1, address _idleCDOPos2Address, uint256 _riskPos2, uint256 _amountPos2) external returns (uint256) {
    require(_amountPos1 > 0 || _amountPos2 > 0, "Not possible to mint a card with 0 amounts");

    // mint the Idle CDO card
    uint256 tokenId = _mint();
    IdleCDOCard _card = new IdleCDOCard();

    if (_amountPos1 > 0) {
      // deposit position 1
      _depositToCard(_card, _idleCDOPos1Address, _riskPos1, _amountPos1);
      _cardSet.push(Card(_riskPos1, _amountPos1, address(_card), _idleCDOPos1Address));
      _cards[tokenId].push(_cardSet.length - 1);
    }

    if (_amountPos2 > 0) {
      // deposit position 2
      _depositToCard(_card, _idleCDOPos2Address, _riskPos2, _amountPos2);
      _cardSet.push(Card(_riskPos2, _amountPos2, address(_card), _idleCDOPos2Address));
      _cards[tokenId].push(_cardSet.length - 1);
    }

    return tokenId;
  }

  function burn(uint256 _tokenId) external {
    require(msg.sender == ownerOf(_tokenId), "burn of risk card that is not own");

    _burn(_tokenId);

    address cardAddress = card(_tokenId,0).cardAddress;

    // withdraw all positions
    for (uint256 i = 0; i < _cards[_tokenId].length; i++) {
      _withdrawFromCard(_tokenId, i);
      delete _cardSet[_cards[_tokenId][i]];
      delete _cards[_tokenId][i];
    }
     delete _cards[_tokenId];
     IdleCDOCard(cardAddress).destroy();
  }

  function card(uint256 _tokenId, uint256 _index) public view returns (Card memory) {
    return _cardSet[_cards[_tokenId][_index]];
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

  function cardIndexes(uint256 _tokenId) public view returns (uint256[] memory _cardIndexes) {
    return _cards[_tokenId];
  }

  function balance(uint256 _tokenId, uint256 _index) public view returns (uint256 balanceAA, uint256 balanceBB) {
    require(_isCardExists(_tokenId, _index), "inexistent card");
    Card memory pos = card(_tokenId, _index);
    IdleCDOCard _card = IdleCDOCard(pos.cardAddress);
    return _card.balance(pos.idleCDOAddress);
  }

  function percentage(uint256 _percentage, uint256 _amount) private pure returns (uint256) {
    require(_percentage < RATIO_PRECISION.add(1), "percentage should be between 0 and 1");
    return _amount.mul(_percentage).div(RATIO_PRECISION);
  }

  function _mint() internal returns (uint256) {
    _tokenIds.increment();

    uint256 newItemId = _tokenIds.current();
    _mint(msg.sender, newItemId);

    return newItemId;
  }

  function _isCardExists(uint256 _tokenId, uint256 _index) internal view virtual returns (bool) {
    return _cards[_tokenId].length != 0 && _cards[_tokenId].length > _index;
  }


  function _depositToCard(IdleCDOCard _card, address _idleCDOAddress, uint256 _risk, uint256 _amount) private {

    // check if _idleCDOAddress exists in idleCDOAddress array
    require(isIdleCDOListed(_idleCDOAddress), "IdleCDO address is not listed in the contract");

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

    _card.mint(_idleCDOAddress, depositAA, depositBB);
  }

  function _withdrawFromCard(uint256 _tokenId, uint256 _index) private {
    Card memory pos = card(_tokenId, _index);

    // burn the card
    IdleCDOCard _card = IdleCDOCard(pos.cardAddress);
    uint256 toRedeem = _card.burn(pos.idleCDOAddress);
    
    // transfer to card owner
    IERC20Detailed underlying = IERC20Detailed(IdleCDO(pos.idleCDOAddress).token());
    underlying.safeTransfer(msg.sender, toRedeem);
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
