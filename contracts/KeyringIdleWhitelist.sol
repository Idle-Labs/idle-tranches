// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

/**
 * @title Keyring Interface
 * @dev A minimal interface for checking credentials using a policy ID and entity address.
 * Developed by Keyring team
 */
interface Keyring {
  /**
   * @notice Checks if a given entity satisfies a policy requirement.
   * @param policyId The ID of the policy to check against.
   * @param entity The address of the entity being checked.
   * @return bool indicating whether the entity satisfies the policy.
   */
  function checkCredential(uint256 policyId, address entity) external view returns (bool);
}

/**
 * @title KeyringIdleWhitelist
 * @dev A contract to manage an administrative whitelist, allowing entities to bypass Keyring credential checks.
 */
contract KeyringIdleWhitelist {
  /* ERRORS */

  /**
   * @notice Error thrown when an unauthorized account attempts to perform an admin-only action.
   * @param account The address of the unauthorized account.
   */
  error NotAdmin(address account);

  /* EVENTS */

  /**
   * @notice Emitted when an entity's whitelist status is updated.
   * @param entity The address of the entity whose whitelist status was updated.
   * @param status The new whitelist status of the entity (true if whitelisted, false otherwise).
   */
  event Whitelist(address indexed entity, bool indexed status);

  /**
   * @notice Emitted when the admin address is changed.
   * @param oldAdmin The address of the previous admin.
   * @param newAdmin The address of the new admin.
   */
  event AdminChange(address indexed oldAdmin, address indexed newAdmin);

  /* STATE VARIABLES */

  /// @notice The address of the deployed Keyring contract.
  address public keyring;

  /// @notice The address of the current admin with permission to manage the whitelist and change admin.
  address public admin;

  /// @notice Mapping to track whitelist status of entities (true if whitelisted, false otherwise).
  mapping(address => bool) public whitelist;

  /* CONSTRUCTOR */

  /**
   * @notice Initializes the contract with the Keyring contract address and sets the deployer as the admin.
   * @param keyring_ The address of the Keyring contract.
   */
  constructor(address keyring_, address admin_) {
    keyring = keyring_;
    admin = admin_;
  }

  /* FUNCTIONS */

  /**
   * @notice Checks if an entity meets a policy's credentials or is whitelisted.
   * @param policyId The ID of the policy to check against.
   * @param entity The address of the entity being checked.
   * @return bool True if the entity is whitelisted or meets the policy's credentials; otherwise, false.
   */
  function checkCredential(uint256 policyId, address entity) external view returns(bool) {
    return whitelist[entity] || Keyring(keyring).checkCredential(policyId, entity);
  }

  /**
   * @notice Updates the admin of the contract to a new address.
   * @param newAdmin The address of the new admin.
   * @dev Only callable by the current admin. Emits an {AdminChange} event.
   */
  function changeAdmin(address newAdmin) external {
    if (msg.sender != admin) {
      revert NotAdmin(msg.sender);
    }
    address oldAdmin = admin;
    admin = newAdmin;
    emit AdminChange(oldAdmin, newAdmin);
  }

  /**
   * @notice Sets or updates the whitelist status of a given entity.
   * @param entity The address of the entity whose whitelist status is to be updated.
   * @param status The new whitelist status (true to whitelist, false to remove from whitelist).
   * @dev Only callable by the current admin. Emits a {Whitelist} event if status changes.
   */
  function setWhitelistStatus(address entity, bool status) external {
    if (msg.sender != admin) {
      revert NotAdmin(msg.sender);
    }
    bool oldStatus = whitelist[entity];
    if (oldStatus == status) {
      return; // No change in status, so no event emission.
    }
    whitelist[entity] = status;
    emit Whitelist(entity, status);
  }


  // /**
  //  * @notice Sets the Keyring contract address.
  //  * @param keyring_ The address of the new Keyring contract.
  //  * @dev Only callable by the current admin. This allows changing the Keyring address if needed.
  //  */
  // function setKeyring(address keyring_) external {
  //   if (msg.sender != admin) {
  //     revert NotAdmin(msg.sender);
  //   }
  //   // No need to check if the address is zero, this will allow only manually whitelisted users.
  //   keyring = keyring_;
  // }
}