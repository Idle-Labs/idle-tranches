// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

/// ============ Imports ============

import { MerkleProofUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol"; // OZ: MerkleProof
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// @title MerkleClaim
/// @notice Modified from https://github.com/Anish-Agnihotri/merkle-airdrop-starter/blob/master/contracts/src/MerkleClaimERC20.sol (no ERC20, cloneable)
/// @author This version @bugduino . Original: Anish Agnihotri <contact@anishagnihotri.com>
contract MerkleClaim {
  address public constant TL_MULTISIG = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;
  /// ============ Mutable storage ============

  /// @notice claimee inclusion root
  bytes32 public merkleRoot;
  /// @notice ERC20 to distribute which must be sent to this contract
  address public token;
  /// @notice Time of deployment
  uint256 public deployTime;
  /// @notice Mapping of addresses who have claimed tokens
  mapping(address => bool) public hasClaimed;

  /// ============ Errors ============

  /// @notice Thrown if address has already claimed
  error AlreadyClaimed();
  /// @notice Thrown if address/amount are not part of Merkle tree
  error NotInMerkle();

  /// ============ Initializer ========

  /// @notice Creates a new MerkleClaimERC20 contract
  /// @param _merkleRoot of claimees
  /// @param _token address of ERC20 to distribute
  function initialize(bytes32 _merkleRoot, address _token) public {
    require(token == address(0)); // Ensure token is not set

    merkleRoot = _merkleRoot; // Update root
    token = _token;

    deployTime = block.timestamp;
  }

  /// ============ Functions ============

  /// @notice Allows claiming tokens if address is part of merkle tree
  /// @param to address of claimee
  /// @param amount of tokens owed to claimee
  /// @param proof merkle proof to prove address and amount are in tree
  function claim(address to, uint256 amount, bytes32[] calldata proof) external {
    // Throw if address has already claimed tokens
    if (hasClaimed[to]) revert AlreadyClaimed();

    // Verify merkle proof, or revert if not in tree,
    // double keccak is preferred https://github.com/OpenZeppelin/merkle-tree#user-content-fn-1-786ed85226485d53b8a7834b144c1642
    bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(to, amount))));
    bool isValidLeaf = MerkleProofUpgradeable.verify(proof, merkleRoot, leaf);
    if (!isValidLeaf) revert NotInMerkle();

    // Set address to claimed
    hasClaimed[to] = true;

    // Transfer tokens to claimee
    IERC20Upgradeable(token).transfer(to, amount);
  }

  function sweep(address to) public {
    require(msg.sender == TL_MULTISIG);
    // allow sweep after 60 days
    require(block.timestamp > deployTime + 60 days);
    address _token = token;
    IERC20Upgradeable(_token).transfer(to, IERC20Upgradeable(_token).balanceOf(address(this)));
  }
}