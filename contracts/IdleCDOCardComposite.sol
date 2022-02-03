// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract IdleCDOCardComposite is ERC721Enumerable {
  using Counters for Counters.Counter;
  using SafeMath for uint256;

  uint256 public constant RATIO_PRECISION = 10**18;

  Counters.Counter private _tokenIds;
  mapping(uint256 => uint256) private _cards;

  mapping(uint256 => uint256[]) private composites;

  constructor() ERC721("IdleCDOCardManager", "ICC") {
  }

  function content(uint256 _tokenId) public view returns (uint256) {
    return _cards[_tokenId];
  }

  function mint() public returns (uint256)  {
    uint256 tokenId = _mint();
    _cards[tokenId] = tokenId*2; //just for testing
    return tokenId;
  } 

  function combine(uint256 _tokenId1, uint256 _tokenId2) public returns (uint256) {
     uint256 tokenId = _mint();
     composites[tokenId] = [_tokenId1, _tokenId2];
     return tokenId;
  }

  function _mint() private returns (uint256) {
    _tokenIds.increment();

    uint256 newItemId = _tokenIds.current();
    _mint(msg.sender, newItemId);

    return newItemId;
  }

  function contentIndexes(uint256 _tokenId) public view returns (uint256[]  memory indexes ) {

    //if leaf and not exist returns 0
    if (composites[_tokenId].length == 0 && _cards[_tokenId] == 0) {
        return new uint256[](0); //undefined
    }

    //if leaf returns the first
    if (composites[_tokenId].length == 0) {
      indexes = new uint256[](1);
      indexes[0] = _tokenId;
      return indexes;
    } 

    //if composite content is a leaf returns the first
    uint256 leaf1 = composites[_tokenId][0];
    uint256 leaf2 = composites[_tokenId][1];
    if (composites[leaf1].length == 0 && composites[leaf2].length == 0) {
        indexes = new uint256[](2); 
        indexes[0] = leaf1;
        indexes[1] = leaf2;
        return indexes;
    }
    
    indexes = new uint256[](3);
    indexes[0] = composites[_tokenId][0];
    uint256[] memory indexes2 = contentIndexes(composites[_tokenId][1]);
    indexes[1] = indexes2[0];
    indexes[2] = indexes2[1];
    // for (uint256 i = 0; i < indexes2.length; i++) {
    //   indexes[i+1] = indexes2[i];
    // }
    return indexes;
  }
  

}