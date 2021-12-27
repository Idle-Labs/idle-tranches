pragma solidity 0.8.7;
import "bl3nd-smart-contracts/contracts/Bl3nd.sol";

contract IdleCDOCardBl3nd is Bl3nd {
  constructor(address _crypto) Bl3nd(_crypto) {}

  function getDeedAddress(uint256 _tokenId) public view returns (address) {
    return address(deeds[_tokenId]);
  }
}
