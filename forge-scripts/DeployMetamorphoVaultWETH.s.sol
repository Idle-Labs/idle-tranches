// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import {TranchesChainlinkOracle} from "../contracts/strategies/morpho/TranchesChainlinkOracle.sol";
import {IMetaMorphoFactory} from "../contracts/interfaces/morpho/IMetaMorphoFactory.sol";
import {IMorphoChainlinkOracleV2} from "../contracts/interfaces/morpho/IMorphoChainlinkOracleV2.sol";
import {IMetaMorphoOracleFactory} from "../contracts/interfaces/morpho/IMetaMorphoOracleFactory.sol";
import {IWETH} from "../contracts/interfaces/IWETH.sol";
import {IAggregatorV3Minimal} from "../contracts/interfaces/morpho/IAggregatorV3Minimal.sol";
import {IMorpho} from "../contracts/interfaces/morpho/IMorpho.sol";
import {IMMVault} from "../contracts/interfaces/morpho/IMMVault.sol";
import {IIdleCDOStrategy} from "../contracts/interfaces/IIdleCDOStrategy.sol";
import {IIdleCDO} from "../contracts/interfaces/IIdleCDO.sol";
import {IdleCDOTranche} from "../contracts/IdleCDOTranche.sol";
import {IERC20Detailed} from "../contracts/interfaces/IERC20Detailed.sol";
import {IERC4626} from "../contracts/interfaces/IERC4626.sol";

contract DeployMetamorphoVaultWETH is Script {
  IMetaMorphoFactory public constant FACTORY = IMetaMorphoFactory(0xA9c3D3a366466Fa809d1Ae982Fb2c46E5fC41101);
  IMetaMorphoOracleFactory public constant ORACLE_FACTORY = IMetaMorphoOracleFactory(0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766);
  IMorpho public constant MORPHO = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
  address internal constant DEPLOYER = 0xE5Dab8208c1F4cce15883348B72086dBace3e64B;
  address internal constant TL_MULTISIG = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;
  address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address internal constant AA_re7WETH = 0x454bB3cb427B21e1c052A080e21A57753cd6969e;
  address internal constant re7WETH_CDO = 0xA8d747Ef758469e05CF505D708b2514a1aB9Cc08;
  address internal constant AA_bbWETH = 0x10036C2E5C441Cdef24A30134b6dF5ebf116205e;
  address internal constant bbWETH_CDO = 0x260D1E0CB6CC9E34Ea18CE39bAB879d450Cdd706;
  address internal constant ADAPTIVE_CURVE_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;

  function run() external {
  // forge script ./forge-scripts/DeployMetamorphoVaultWETH.s.sol \
  // --fork-url $ETH_RPC_URL \
  // --ledger \
  // --broadcast \
  // --optimize \
  // --optimizer-runs 99999 \
  // --verify \
  // --with-gas-price 50000000000 \
  // --sender "0xE5Dab8208c1F4cce15883348B72086dBace3e64B" \
  // --slow \
  // -vvv

    vm.startBroadcast();
    (IMorpho.MarketParams memory re7Params, bytes32 re7Id) = _initializeTrancheMarket(AA_re7WETH);

    IERC20Detailed(WETH).approve(address(MORPHO), type(uint256).max);
    IERC20Detailed(AA_re7WETH).approve(address(MORPHO), type(uint256).max);
    // supply 0.01 tranche tokens as collateral, 
    MORPHO.supplyCollateral(re7Params, 1e16, DEPLOYER, '');
    // supply 0.01 to the market and borrow 0.009 to achieve 90% UR
    MORPHO.supply(re7Params, 1e16, 0, DEPLOYER, '');
    MORPHO.borrow(re7Params, 9e15, 0, DEPLOYER, DEPLOYER);
    vm.stopBroadcast();
  }

  function _createOracle(TranchesChainlinkOracle adapter, uint256 collateralDecimals, uint256 loanDecimals) internal returns (IMorphoChainlinkOracleV2 oracle) {
    oracle = ORACLE_FACTORY.createMorphoChainlinkOracleV2(
      IERC4626(address(0)), 
      1, 
      adapter, 
      IAggregatorV3Minimal(address(0)),
      collateralDecimals,
      IERC4626(address(0)), 
      1, 
      IAggregatorV3Minimal(address(0)), 
      IAggregatorV3Minimal(address(0)), 
      loanDecimals, 
      '0x'
    );
    return oracle;
  }

  function _initializeTrancheMarket(address collateralToken) internal returns (IMorpho.MarketParams memory marketParams, bytes32 id) {
    address loanToken = IIdleCDO(IdleCDOTranche(collateralToken).minter()).token();
    // 1. Deploy oracle for collateral token
    TranchesChainlinkOracle adapter = new TranchesChainlinkOracle(collateralToken);
    IMorphoChainlinkOracleV2 oracle = _createOracle(adapter, IERC20Detailed(collateralToken).decimals(), IERC20Detailed(loanToken).decimals());
    // 2. Create market in morpho blue
    marketParams = IMorpho.MarketParams({
      loanToken: loanToken,
      collateralToken: collateralToken,
      oracle: address(oracle),
      irm: ADAPTIVE_CURVE_IRM,
      lltv: 98 * 1e16 // 98%
    });
    id = computeId(marketParams);
    MORPHO.createMarket(marketParams);
  }

  // function _createMetaMorphoVault(address loanToken, IMorpho.MarketParams[] memory params) internal returns (address mmVault) {
  //   // loop through params and see if market loanToken is the same as loanToken param
  //   for (uint256 i = 0; i < params.length; i++) {
  //     require(params[i].collateralToken != address(0), "loanToken do not match");
  //   }

  //   // idle market 
  //   IMorpho.MarketParams memory idleParams = IMorpho.MarketParams({
  //     loanToken: WETH,
  //     collateralToken: address(0),
  //     oracle: address(0),
  //     irm: address(0),
  //     lltv: 0
  //   });
  //   string memory symbol = IERC20Detailed(loanToken).symbol();
  //   // Deploy metamorpho vault (https://docs.morpho.org/contracts/metamorpho/guides/become-a-curator/setup)
  //   IMMVault vault = FACTORY.createMetaMorpho(
  //     DEPLOYER,
  //     86400, // 1 day
  //     loanToken,
  //     string(abi.encodePacked("Idle Finance ", symbol)),
  //     string(abi.encodePacked("idle", symbol)),
  //     "1"
  //   );
  //   mmVault = address(vault);
  //   // set params and market caps
  //   vault.setCurator(TL_MULTISIG);
  //   vault.setIsAllocator(TL_MULTISIG, true);
  //   vault.submitGuardian(TL_MULTISIG);
  //   vault.setFeeRecipient(TL_MULTISIG);
  //   vault.setFee(50000000000000000); // 5%
  //   vault.setSkimRecipient(TL_MULTISIG);
  //   vault.submitCap(idleParams, type(uint184).max);
  //   for (uint256 i = 0; i < params.length; i++) {
  //     vault.submitCap(params[i], 10000 * 1e18);
  //   }
  //   skip(1 days);
  //   vault.acceptCap(idleParams);
  //   for (uint256 i = 0; i < params.length; i++) {
  //     vault.acceptCap(params[i]);
  //   }
  //   bytes32[] memory supplyQueue = new bytes32[](params.length);
  //   for (uint256 i = 0; i < params.length; i++) {
  //     supplyQueue[i] = computeId(params[i]);
  //   }
  //   vault.setSupplyQueue(supplyQueue);
  //   vault.transferOwnership(TL_MULTISIG);

  //   // vm.prank(TL_MULTISIG);
  //   // IMMVault(mmVault).acceptOwnership();
  // }

  /// @notice Returns the id of the market `marketParams`.
  function computeId(IMorpho.MarketParams memory marketParams) internal pure returns (bytes32 marketParamsId) {
    // 5 * 32 bytes
    assembly {
      marketParamsId := keccak256(marketParams, 160)
    }
  }
}