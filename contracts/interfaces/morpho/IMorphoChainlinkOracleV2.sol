// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IERC4626} from "../IERC4626.sol";
import {IOracle} from "./IOracle.sol";
import {IAggregatorV3Minimal} from "./IAggregatorV3Minimal.sol";

/// @title IMorphoChainlinkOracleV2
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Interface of MorphoChainlinkOracleV2.
interface IMorphoChainlinkOracleV2 is IOracle {
  /// @notice Returns the address of the base ERC4626 vault.
  function BASE_VAULT() external view returns (IERC4626);

  /// @notice Returns the base vault conversion sample.
  function BASE_VAULT_CONVERSION_SAMPLE() external view returns (uint256);

  /// @notice Returns the address of the quote ERC4626 vault.
  function QUOTE_VAULT() external view returns (IERC4626);

  /// @notice Returns the quote vault conversion sample.
  function QUOTE_VAULT_CONVERSION_SAMPLE() external view returns (uint256);

  /// @notice Returns the address of the first base feed.
  function BASE_FEED_1() external view returns (IAggregatorV3Minimal);

  /// @notice Returns the address of the second base feed.
  function BASE_FEED_2() external view returns (IAggregatorV3Minimal);

  /// @notice Returns the address of the first quote feed.
  function QUOTE_FEED_1() external view returns (IAggregatorV3Minimal);

  /// @notice Returns the address of the second quote feed.
  function QUOTE_FEED_2() external view returns (IAggregatorV3Minimal);

  /// @notice Returns the price scale factor, calculated at contract creation.
  function SCALE_FACTOR() external view returns (uint256);
}