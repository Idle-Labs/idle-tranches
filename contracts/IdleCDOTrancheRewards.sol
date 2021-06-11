// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

contract IdleCDOTrancheRewards {
  address public idleCDO;
  address public tranche;
  // address[] public rewards;

  constructor(address _trancheToken) {
    idleCDO = msg.sender;
    tranche = _trancheToken;
    // todo set rewards
  }

  // TODO add stake, unstake, funds recover, get rewards etc
}
