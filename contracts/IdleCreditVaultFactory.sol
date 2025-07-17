// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IdleCDOEpochVariant, IdleCDO} from "./IdleCDOEpochVariant.sol";
import {IdleCDOEpochQueue} from "./IdleCDOEpochQueue.sol";
import {IdleCreditVault} from "./strategies/idle/IdleCreditVault.sol";

contract IdleCreditVaultFactory {
  event CreditVaultDeployed(address proxy);
  event StrategyDeployed(address proxy);
  event QueueDeployed(address proxy);

  struct TransparentProxyData {
    address implementation;
    address proxyAdmin;
    bytes initializeData;
  }

  struct CreditVaultParams {
    uint256 apr;
    uint256 epochDuration;
    uint256 bufferPeriod;
    uint256 instantWithdrawDelay;
    uint256 instantWithdrawAprDelta;
    bool disableInstantWithdraw;
    address keyring;
    uint256 keyringPolicy;
    bool keyringAllowWithdraw;
    uint256 fees;
  }

  function deployCreditVault(
    TransparentProxyData memory cvData,
    TransparentProxyData memory strategyData,
    CreditVaultParams memory cvParams,
    address queueImplementation,
    address owner
  ) external {
    // Deploy and initialize strategy
    IdleCreditVault strategy = IdleCreditVault(_deployProxy(strategyData));
    emit StrategyDeployed(address(strategy));

    // get guardian address from cvData because it will be overwritten in _replaceInitializeData
    // and we need to set it after deploying the credit vault
    address guardian = _getGuardian(cvData.initializeData);
    // Replace strategy address with the deployed strategy address
    // and owner address with address(this) in the CV initialize data
    cvData.initializeData = _replaceInitializeData(cvData.initializeData, address(strategy));

    // Deploy and initialize credit vault
    IdleCDOEpochVariant cv = IdleCDOEpochVariant(_deployProxy(cvData));
    emit CreditVaultDeployed(address(cv));

    _setCVParams(cv, strategy, cvParams);

    if (queueImplementation != address(0)) {
      // Deploy and initialize strategy
      IdleCDOEpochQueue queue = IdleCDOEpochQueue(_deployProxy(
        TransparentProxyData({
          implementation: queueImplementation,
          proxyAdmin: strategyData.proxyAdmin, // same as strategy
          initializeData: abi.encodeWithSelector(
            IdleCDOEpochQueue.initialize.selector,
            address(cv), // Use the deployed credit vault address
            owner,
            true // Always AA tranche
          )
        })
      ));
      emit QueueDeployed(address(queue));
    }

    cv.setFeeReceiver(owner);
    cv.setGuardian(guardian);
    // Transfer ownership of strategy and credit vault to owner
    strategy.transferOwnership(owner);
    cv.transferOwnership(owner);
  }

  function _deployProxy(TransparentProxyData memory data) internal returns (address) {
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      data.implementation,
      data.proxyAdmin,
      data.initializeData
    );
    return address(proxy);
  }

  function _setCVParams(
    IdleCDOEpochVariant cv,
    IdleCreditVault strategy,
    CreditVaultParams memory par
  ) internal {
    cv.setUnlentPerc(0);
    cv.setEpochParams(par.epochDuration, par.bufferPeriod);
    cv.setInstantWithdrawParams(par.instantWithdrawDelay, par.instantWithdrawAprDelta, par.disableInstantWithdraw);
    cv.setKeyringParams(par.keyring, par.keyringPolicy, par.keyringAllowWithdraw);
    cv.setFee(par.fees);
    // setAprs should be done before setWhitelistedCDO
    strategy.setAprs(par.apr, par.apr * (par.epochDuration + par.bufferPeriod) / par.epochDuration);
    strategy.setWhitelistedCDO(address(cv));
  }

  function _getGuardian(bytes memory cvData) internal pure returns (address guardian) {
    assembly {
      // The guardian address is the 4th argument in the initialize function.
      // It is located at offset 0x64 (4 bytes for selector + 3 * 32 bytes for previous arguments).
      // The memory address is `cvData` + 0x20 (content start) + 0x64 = `cvData` + 0x84.
      guardian := mload(add(cvData, 0x84))
    }
  }

  function _replaceInitializeData(bytes memory data, address strategyAddress) internal view returns (bytes memory) {
    // The data is ABI encoded calldata for `initialize(uint256, address, address, address, address, address, uint256)`
    // We want to replace two arguments:
    // 1. The 4th argument (owner) with `address(this)`.
    // 2. The 6th argument (strategy) with `strategyAddress`.
    //
    // Memory layout of `data`:
    // - 0x00: data length (32 bytes)
    // - 0x20: data content starts here
    //
    // Content layout:
    // - 0x20: function selector (4 bytes)
    // - 0x24: 1st argument (_limit)
    // - 0x44: 2nd argument (_guardedToken)
    // - 0x64: 3rd argument (_governanceFund)
    // - 0x84: 4th argument (owner) <--- TARGET 1
    // - 0xa4: 5th argument (rebalancer)
    // - 0xc4: 6th argument (strategy) <--- TARGET 2
    assembly {
      // Replace the owner (4th argument) with this contract's address.
      // The 4th argument is after the selector (4 bytes) and 3 preceding arguments (3 * 32 bytes).
      // Offset = 4 + 96 = 100 bytes from the start of the content.
      // The memory address is `data` + 0x20 (content start) + 100 = `data` + 0x84.
      // The `address` opcode returns the address of the current contract.
      mstore(add(data, 0x84), address())

      // Replace the strategy address (6th argument).
      // The 6th argument is after the selector (4 bytes) and 5 preceding arguments (5 * 32 bytes).
      // Offset = 4 + 160 = 164 bytes from the start of the content.
      // The memory address is `data` + 0x20 + 164 = `data` + 0xc4.
      mstore(add(data, 0xc4), strategyAddress)
    }

    return data;
  }
}
