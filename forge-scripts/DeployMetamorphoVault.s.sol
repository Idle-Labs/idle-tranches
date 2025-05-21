// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Script.sol";
import {TranchesChainlinkOracle} from "../contracts/strategies/morpho/TranchesChainlinkOracle.sol";
import {IMetaMorphoFactory} from "../contracts/interfaces/morpho/IMetaMorphoFactory.sol";
import {IMorphoChainlinkOracleV2} from "../contracts/interfaces/morpho/IMorphoChainlinkOracleV2.sol";
import {IMetaMorphoOracleFactory} from "../contracts/interfaces/morpho/IMetaMorphoOracleFactory.sol";
import {IAggregatorV3Minimal} from "../contracts/interfaces/morpho/IAggregatorV3Minimal.sol";
import {IMorpho} from "../contracts/interfaces/morpho/IMorpho.sol";
import {IMMVault} from "../contracts/interfaces/morpho/IMMVault.sol";
import {IIdleCDOStrategy} from "../contracts/interfaces/IIdleCDOStrategy.sol";
import {IIdleCDO} from "../contracts/interfaces/IIdleCDO.sol";
import {IdleCDOTranche} from "../contracts/IdleCDOTranche.sol";
import {IERC20Detailed} from "../contracts/interfaces/IERC20Detailed.sol";
import {IERC4626} from "../contracts/interfaces/IERC4626.sol";

contract DeployMetamorphoVault is Script {
  IMetaMorphoFactory public constant FACTORY = IMetaMorphoFactory(0x1897A8997241C1cD4bD0698647e4EB7213535c24);
  IMetaMorphoOracleFactory public constant ORACLE_FACTORY = IMetaMorphoOracleFactory(0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766);
  IMorpho public constant MORPHO = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
  address internal constant DEPLOYER = 0xE5Dab8208c1F4cce15883348B72086dBace3e64B;
  address internal constant TL_MULTISIG = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;
  address internal constant ADAPTIVE_CURVE_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
  // Idle Vault Params
  address internal constant LOAN_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
  address internal constant AA_tranche_1 = 0x45054c6753b4Bce40C5d54418DabC20b070F85bE;
  // Morpho Vault Params
  uint256 internal constant MORPHO_LLTV = 98; // 98%
  uint256 internal constant MORPHO_VAULT_FEE = 50000000000000000; // 5%
  uint256 internal constant MORPHO_TRANCHE_CAP = 10_000_000 * 1e6; // 10M
  string internal constant MORPHO_VAULT_NAME_SUFFIX = "Pareto Fasanara ";
  string internal constant MORPHO_VAULT_SYMBOL_SUFFIX = "parFas";

  function run() external {
    // forge script ./forge-scripts/DeployMetamorphoVault.s.sol \
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
    _setUpMorphoVault();
    vm.stopBroadcast();

    console.log('IMPORTANT: Call acceptOwnership in morpho vault with: ', TL_MULTISIG);
  }

  function _setUpMorphoVault() public {
    (IMorpho.MarketParams memory tranche1Params, bytes32 marketId) = _initializeTrancheMarket(AA_tranche_1);

    uint256 decimals = IERC20Detailed(LOAN_TOKEN).decimals();
    IERC20Detailed(LOAN_TOKEN).approve(address(MORPHO), type(uint256).max);
    IERC20Detailed(AA_tranche_1).approve(address(MORPHO), type(uint256).max);
    // supply 1 tranche tokens as collateral, 
    MORPHO.supplyCollateral(tranche1Params, 1e18, DEPLOYER, '');
    // supply 1 to the market and borrow 0.9 to achieve 90% UR
    uint256 supplyAmount = 10 ** (decimals);
    MORPHO.supply(tranche1Params, supplyAmount, 0, DEPLOYER, '');
    MORPHO.borrow(tranche1Params, supplyAmount * 90 / 100, 0, DEPLOYER, DEPLOYER);
    
    // IMorpho.MarketParams[] memory params = new IMorpho.MarketParams[](1);
    // params[0] = tranche1Params;
    // address mmVault = _createMetaMorphoVault(LOAN_TOKEN, params);
    // console.log('mmVault.address ', address(mmVault));
    console.log('market.id       ');
    console.logBytes32(marketId);
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
    console.log('oracle.address ', address(oracle));
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
      lltv: MORPHO_LLTV * 1e16 // 98%
    });
    id = computeId(marketParams);
    MORPHO.createMarket(marketParams);
  }

  function _createMetaMorphoVault(address loanToken, IMorpho.MarketParams[] memory params) internal returns (address mmVault) {
    // loop through params and see if market loanToken is the same as loanToken param
    for (uint256 i = 0; i < params.length; i++) {
      require(params[i].collateralToken != address(0), "loanToken do not match");
    }

    string memory symbol = IERC20Detailed(loanToken).symbol();
    // Deploy metamorpho vault (https://docs.morpho.org/curation/tutorials/vault-creation/)
    IMMVault vault = FACTORY.createMetaMorpho(
      DEPLOYER,
      0, // timelock is set to 0 initially
      loanToken,
      string(abi.encodePacked(MORPHO_VAULT_NAME_SUFFIX, symbol)),
      string(abi.encodePacked(MORPHO_VAULT_SYMBOL_SUFFIX, symbol)),
      "1"
    );
    mmVault = address(vault);
    // set params and market caps
    vault.setCurator(TL_MULTISIG);
    vault.setIsAllocator(TL_MULTISIG, true);
    vault.submitGuardian(TL_MULTISIG);
    vault.setFeeRecipient(TL_MULTISIG);
    vault.setFee(MORPHO_VAULT_FEE); // 5%
    vault.setSkimRecipient(TL_MULTISIG);

    // idle market 
    IMorpho.MarketParams memory idleParams = IMorpho.MarketParams({
      loanToken: LOAN_TOKEN,
      collateralToken: address(0),
      oracle: address(0),
      irm: address(0),
      lltv: 0
    });

    vault.submitCap(idleParams, type(uint184).max);
    for (uint256 i = 0; i < params.length; i++) {
      vault.submitCap(params[i], MORPHO_TRANCHE_CAP);
    }
    vault.acceptCap(idleParams);
    for (uint256 i = 0; i < params.length; i++) {
      vault.acceptCap(params[i]);
    }
    bytes32[] memory supplyQueue = new bytes32[](params.length);
    for (uint256 i = 0; i < params.length; i++) {
      supplyQueue[i] = computeId(params[i]);
    }
    vault.setSupplyQueue(supplyQueue);
    vault.submitTimelock(1 days);
    vault.transferOwnership(TL_MULTISIG);
  }

  /// @notice Returns the id of the market `marketParams`.
  function computeId(IMorpho.MarketParams memory marketParams) internal pure returns (bytes32 marketParamsId) {
    // 5 * 32 bytes
    assembly {
      marketParamsId := keccak256(marketParams, 160)
    }
  }
}