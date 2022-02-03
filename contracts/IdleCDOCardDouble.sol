// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract IdleCDOCardDouble is ERC721Enumerable {
  using Counters for Counters.Counter;
  using SafeMath for uint256;

  uint256 public constant RATIO_PRECISION = 10**18;

  Counters.Counter private _tokenIds;
  mapping(uint256 => uint256) private _content;

  mapping(uint256 => uint256[]) private composites; // binary
  mapping(uint256 => bool) private isCombined;

  constructor() ERC721("IdleCDOCardManager", "ICC") {
  }

  function content(uint256 _tokenId) public view returns (uint256) {
    return _content[_tokenId];
  }

  function mint() public returns (uint256)  {
    uint256 tokenId = _mint();
    _content[tokenId] = tokenId*2; //just for testing
    return tokenId;
  } 

  function combine(uint256 _tokenId1, uint256 _tokenId2) public returns (uint256) {
     require(isLeaf(_tokenId1) && isLeaf(_tokenId2), "Only leafs can be combined");
     require(!isCombined[_tokenId1] && !isCombined[_tokenId2], "Leafs were already combined");
     require(isContentExist(_tokenId1) && isContentExist(_tokenId2), "There are inexistent leafs");
     require(_tokenId1 != _tokenId2, "Can't combine same leafs");
     require(msg.sender == ownerOf(_tokenId1) && msg.sender == ownerOf(_tokenId2), "Only owner can combine leafs"); 
     
     transferFrom(msg.sender, address(this), _tokenId1);
     transferFrom(msg.sender, address(this), _tokenId2);
     
     uint256 tokenId = _mint();
     composites[tokenId] = [_tokenId1, _tokenId2];
     isCombined[_tokenId1] = true;
     isCombined[_tokenId2] = true;
     return tokenId;
  }

  function uncombine(uint256 _tokenId) public returns (uint256 tokenId1, uint256 tokenId2) {
    require(!isNotExist(_tokenId), "The token does not exist");
    require(!isLeaf(_tokenId), "Can not uncombine a non-combined token");
    require(msg.sender == ownerOf(_tokenId), "Only owner can uncombine combined leafs");
    
    tokenId1 = composites[_tokenId][0];
    tokenId2 = composites[_tokenId][1];

    isCombined[tokenId1] = false;
    isCombined[tokenId2] = false;

     _burn(_tokenId);

    this.transferFrom(address(this), msg.sender, tokenId1);
    this.transferFrom(address(this), msg.sender, tokenId2);
  } 

  function _mint() private returns (uint256) {
    _tokenIds.increment();

    uint256 newItemId = _tokenIds.current();
    _mint(msg.sender, newItemId);

    return newItemId;
  }

  function contentIndexes(uint256 _tokenId) public view returns (uint256[]  memory indexes ) {

    //if leaf and not exist returns 0
    if (isLeaf(_tokenId)&& !isContentExist(_tokenId)) {
        return new uint256[](0); //undefined
    }

    //if leaf returns the first
    if (isLeaf(_tokenId)) {
      indexes = new uint256[](1);
      indexes[0] = _tokenId;
      return indexes;
    } 

    //composite content 
    indexes = new uint256[](2);
    indexes[0] = composites[_tokenId][0];
    indexes[1] = composites[_tokenId][1];
    return indexes;
 
  }

  function isContentExist(uint256 _tokenId) private view returns (bool) {
    return _content[_tokenId] != 0;
  }
  function isLeaf(uint256 _tokenId) private view returns (bool) {
    return composites[_tokenId].length == 0;
  }

  function isNotExist(uint256 _tokenId) private view returns (bool) {
    return isLeaf(_tokenId)&& !isContentExist(_tokenId);
  }

}