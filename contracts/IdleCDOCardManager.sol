// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

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

  function mint(address _idleCDOAddress, uint256 _risk, uint256 _amount) public returns (uint256) {
    // assume only mint _idleCDOAddress if _amountFEI is 0
    return mint(_idleCDOAddress, _risk, _amount, address(0),0,0);
  }

  function mint(address _idleCDODAIAddress, uint256 _riskDAI, uint256 _amountDAI, address _idleCDOFEIAddress, uint256 _riskFEI, uint256 _amountFEI) public returns (uint256) {
    require(_amountDAI > 0 || _amountFEI > 0, "Not possible to mint a card with 0 amounts");
    
    // mint the Idle CDO card
    uint256 tokenId = _mint();
    IdleCDOCard _card = new IdleCDOCard();

    if (_amountDAI > 0) {
       // deposit DAI
      _depositToCard(_card, _idleCDODAIAddress, _riskDAI, _amountDAI);
      _cardSet.push(Card(_riskDAI, _amountDAI, address(_card), _idleCDODAIAddress));
      _cards[tokenId].push(_cardSet.length -1);
    }

    if (_amountFEI > 0) {
      // deposit FEI
      _depositToCard(_card, _idleCDOFEIAddress, _riskFEI, _amountFEI);
      _cardSet.push(Card(_riskFEI, _amountFEI, address(_card), _idleCDOFEIAddress));
      _cards[tokenId].push(_cardSet.length -1);
    }

    return tokenId;
  }

    function burn(uint256 _tokenId) public {
    require(msg.sender == ownerOf(_tokenId), "burn of risk card that is not own");

    _burn(_tokenId);

    //////////////////////////// DAI CARD ////////////////////////////
    // get the card
    Card memory posDAI = card(_tokenId,0);
    if (posDAI.cardAddress != address(0)) {
      IdleCDOCard _cardDAI = IdleCDOCard(posDAI.cardAddress);
      // burn the card
      uint256 toRedeemDAI = _cardDAI.burn(posDAI.idleCDOAddress);
      // transfer to card owner
      IERC20Detailed underlying = IERC20Detailed(IdleCDO(posDAI.idleCDOAddress).token());
      underlying.safeTransfer(msg.sender, toRedeemDAI);
    }

    //////////////////////////// FEI CARD ////////////////////////////
    // get the card

    if(_cards[_tokenId].length<2){
      return;
    }

    Card memory posFEI = card(_tokenId,1);
    if (posFEI.cardAddress != address(0)) {
      IdleCDOCard _cardFEI = IdleCDOCard(posFEI.cardAddress);
      // burn the card
       uint256 toRedeemFEI = _cardFEI.burn(posFEI.idleCDOAddress);
      // transfer to card owner
      IERC20Detailed underlying = IERC20Detailed(IdleCDO(posFEI.idleCDOAddress).token());
      underlying.safeTransfer(msg.sender, toRedeemFEI);
    }

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

  function cardIndexes(uint256 _tokenId) public view  returns (uint256[] memory _cardIndexes) {
      return _cards[_tokenId]; 
   }

  function balance(uint256 _tokenId, uint256 _index) public view returns (uint256 balanceAA, uint256 balanceBB) {
    require(_isCardExists(_tokenId, _index), "inexistent card");
    Card memory pos = card(_tokenId,_index);
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

  function _isCardExists(uint256 _tokenId, uint256 _index) internal view virtual  returns (bool) {
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

    _card.mint(_idleCDOAddress,depositAA, depositBB);
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
