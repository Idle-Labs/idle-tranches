pragma solidity 0.8.7;
import "bl3nd-smart-contracts/contracts/Bl3nd.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract IdleCDOCardBl3nd is Bl3nd,ERC721Enumerable {
  constructor(address _crypto) Bl3nd(_crypto) {}

  function getDeedAddress(uint256 _tokenId) public view returns (address) {
    return address(deeds[_tokenId]);
  }

  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC721Enumerable) returns (bool) {
        return ERC721Enumerable.supportsInterface(interfaceId);
  }

  function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override (ERC721, ERC721Enumerable) {
        ERC721Enumerable._beforeTokenTransfer(from, to, tokenId);
  }
}
