// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./IdleCDO.sol";
import "./IdleCDOCard.sol";
import "./IdleCDOCardBl3nd.sol";

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
  IdleCDOCardBl3nd private bl3nd;

  Counters.Counter private _tokenIds;
  mapping(uint256 => Card) private _cards;

  constructor(address[] memory _idleCDOAddress) ERC721("IdleCDOCardManager", "ICC") {
    for (uint256 i = 0; i < _idleCDOAddress.length; i++) {
      idleCDOs.push(IdleCDO(_idleCDOAddress[i]));
    }
    bl3nd = new IdleCDOCardBl3nd(address(this));
  }

  function getIdleCDOs() public view returns (IdleCDO[] memory) {
    return idleCDOs;
  }

  function combine(address _idleCDODAIAddress, uint256 _riskDAI, uint256 _amountDAI,address _idleCDOFEIAddress, uint256 _riskFEI, uint256 _amountFEI) public {
     require(_amountDAI > 0 ||  _amountFEI > 0, "Not possible to mint a card with 0 amounts");
     if(_amountDAI == 0) { 
       mint(_idleCDOFEIAddress, _riskFEI, _amountFEI);
       return;
     }
     if(_amountFEI == 0) {
       mint(_idleCDODAIAddress, _riskDAI, _amountDAI);
       return;
     }
     uint256 cardDAI = mint(_idleCDODAIAddress, _riskDAI, _amountDAI);
     uint256 cardFEI = mint(_idleCDOFEIAddress, _riskFEI, _amountFEI);

     transferFrom(msg.sender, address(this), cardDAI); 
     transferFrom(msg.sender, address(this), cardFEI);

     this.approve(address(bl3nd), cardDAI);
     this.approve(address(bl3nd), cardFEI);
      
     bl3nd.blend(this, cardDAI, this, cardFEI);
     
     uint256 _blendTokenId = blendTokenId(cardDAI, cardFEI);

     bl3nd.transferFrom(address(this), msg.sender, _blendTokenId);
  }

  function mint(address _idleCDOAddress, uint256 _risk, uint256 _amount) public returns (uint256) {
    // check if _idleCDOAddress exists in idleCDOAddress array
    require(isIdleCDOListed(_idleCDOAddress), "IdleCDO address is not listed in the contract");

    IdleCDOCard _card = new IdleCDOCard(_idleCDOAddress);
    IERC20Detailed underlying  = IERC20Detailed(IdleCDO(_idleCDOAddress).token());

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

  function card(uint256 _tokenId) public view returns (Card memory) {
    return _cards[_tokenId];
  }

  function cardGroup(uint256 _tokenId) public view returns (uint256[]  memory tokenCardIds ) {
    tokenCardIds = new uint256[](2);
    if(_cards[_tokenId].cardAddress!=address(0)) {
        tokenCardIds[0] = _tokenId;
        return tokenCardIds;
    }
  
    address deedAddress = bl3nd.getDeedAddress(_tokenId);
    if(deedAddress == address(0)) {
      return tokenCardIds;
    }
  
    Bl3ndDeed deed = Bl3ndDeed(deedAddress);
    tokenCardIds[0] = deed.id0();
    tokenCardIds[1] = deed.id1();
  
    return tokenCardIds;
  }
  

  function burn(uint256 _tokenId) public returns (uint256 toRedeem) {
    require(msg.sender == ownerOf(_tokenId), "burn of risk card that is not own");

    _burn(_tokenId);

    Card memory pos = card(_tokenId);
    IdleCDOCard _card = IdleCDOCard(pos.cardAddress);
    toRedeem = _card.burn();

    // transfer to card owner
    IERC20Detailed underlying  = IERC20Detailed(IdleCDO(pos.idleCDOAddress).token());
    underlying.safeTransfer(msg.sender, toRedeem);
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
    Card memory pos = card(_tokenId);
    require(pos.cardAddress != address(0), "inexistent card");
    IdleCDOCard _card = IdleCDOCard(pos.cardAddress);
    return _card.balance();
  }

  function blendTokenId(uint256 id0,  uint256 id1) public view returns (uint256) {
    return bl3nd.blendTokenId(this, id0, this, id1);
  }
  function idsFromBlend(uint256 _blendTokenId) public view returns (uint256 id0, uint256 id1) {
    address deedAddress= bl3nd.getDeedAddress(_blendTokenId);
    Bl3ndDeed deed = Bl3ndDeed(deedAddress);
    id0 = deed.id0();
    id1 = deed.id1();
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

  function isIdleCDOListed(address _idleCDOAddress) private view returns (bool) {
    for (uint256 i = 0; i < idleCDOs.length; i++) {
      if (address(idleCDOs[i]) == _idleCDOAddress) {
        return true;
      }
    }
    return false;
  }

  function balanceOf(address owner) public view virtual override returns (uint256) {
     return super.balanceOf(owner) + bl3nd.balanceOf(owner);
  }

  function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual override returns (uint256) {
     require(index < balanceOf(owner),"No Card found for index");

     uint256 cardsBalance = super.balanceOf(owner);

     if (cardsBalance > index) {
        return super.tokenOfOwnerByIndex(owner,index);
     }

     uint256 blendIndex = index - cardsBalance;
     return bl3nd.tokenOfOwnerByIndex(owner,blendIndex);
  }

}