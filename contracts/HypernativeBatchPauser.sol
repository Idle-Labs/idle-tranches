// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IIdleCDO} from "./interfaces/IIdleCDO.sol";

error NotAllowed();

contract HypernativeBatchPauser is Ownable {
  address public pauser;
  address[] public protectedContracts;

  constructor(address _pauser, address[] memory _protectedContracts) {
    pauser = _pauser;
    for (uint i = 0; i < _protectedContracts.length; ++i) {
      protectedContracts.push(_protectedContracts[i]);
    }
  }

  /// @notice pause all the protected contracts
  /// @dev only the owner or the pauser can call this function
  function pauseAll() external {
    if (msg.sender != pauser && msg.sender != owner()) {
      revert NotAllowed();
    }
    uint256 protectedContractLen = protectedContracts.length;
    for (uint256 i = 0; i < protectedContractLen;) {
      IIdleCDO(protectedContracts[i]).emergencyShutdown();
      unchecked {
        ++i;
      }
    }
  }

  /// @notice replace the protected contracts
  /// @param _protectedContracts the new protected contracts
  function replaceProtectedContracts(address[] memory _protectedContracts) external onlyOwner {
    assembly {
      sstore(protectedContracts.slot, mload(_protectedContracts))
    }
    uint256 _protectedContractsLength = _protectedContracts.length;
    for (uint256 i = 0; i < _protectedContractsLength;) {
      protectedContracts[i] = _protectedContracts[i];
      unchecked {
        ++i;
      }
    }
  }

  /// @notice add new protected contracts
  /// @param _protectedContracts the new protected contracts
  function addProtectedContracts(address[] memory _protectedContracts) public onlyOwner {
    uint256 _protectedContractsLength = _protectedContracts.length;
    for (uint i = 0; i < _protectedContractsLength;) {
      protectedContracts.push(_protectedContracts[i]);
      unchecked {
        ++i;
      }
    }
  }

  /// @notice replace the pauser address
  /// @param _pauser the new pauser address
  function setPauser(address _pauser) external onlyOwner {
    pauser = _pauser;
  }
}