// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/utils/Counters.sol";

import "../ERC721SimpleComposite.sol";

contract MockERC721SimpleComposite is ERC721SimpleComposite {
  using Counters for Counters.Counter;

  Counters.Counter private _tokenIds;
  mapping(uint256 => uint256) private _content;

  constructor() ERC721("MockERC721", "MCK") {}

  function content(uint256 _tokenId) public view returns (uint256) {
    return _content[_tokenId];
  }

  function mint() public returns (uint256) {
    uint256 tokenId = _mint();
    _content[tokenId] = tokenId * 2; //just for testing
    return tokenId;
  }

  function _mint() internal override returns (uint256) {
    _tokenIds.increment();

    uint256 newItemId = _tokenIds.current();
    _mint(msg.sender, newItemId);

    return newItemId;
  }

  function _isLeafExists(uint256 _tokenId) internal view virtual override returns (bool) {
    return _content[_tokenId] != 0;
  }

  function combine(uint256 _tokenId1, uint256 _tokenId2) public returns (uint256) {
    return _combine(_tokenId1, _tokenId2);
  }

  function uncombine(uint256 _tokenId) public returns (uint256 tokenId1, uint256 tokenId2) {
    return _uncombine(_tokenId);
  }
}
