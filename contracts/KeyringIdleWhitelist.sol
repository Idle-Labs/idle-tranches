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
 * @dev Denies locally blacklisted entities before checking the administrative whitelist or Keyring credentials.
 */
contract KeyringIdleWhitelist {
  /* ERRORS */

  /**
   * @notice Error thrown when an unauthorized account attempts to perform an admin-only action.
   * @param account The address of the unauthorized account.
   */
  error NotAdmin(address account);

  /* EVENTS */

  /// @notice Emitted when an entity's blacklist status changes.
  event Blacklist(address indexed entity, bool indexed status);

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

  /// @notice Tracks entities denied by the local admin.
  mapping(address => bool) public blacklist;

  /* CONSTRUCTOR */

  /**
   * @notice Initializes the adapter with the Keyring contract address and admin.
   * @param keyring_ The address of the Keyring contract.
   * @param admin_ The initial administrator.
   */
  constructor(address keyring_, address admin_) {
    keyring = keyring_;
    admin = admin_;
  }

  /* FUNCTIONS */

  /**
   * @notice Checks whether an entity outside the local blacklist is whitelisted or meets a policy's credentials.
   * @param policyId The ID of the policy to check against.
   * @param entity The address of the entity being checked.
   * @return bool Whether the entity is eligible for the policy.
   */
  function checkCredential(uint256 policyId, address entity) external view returns(bool) {
    return !blacklist[entity] && (whitelist[entity] || Keyring(keyring).checkCredential(policyId, entity));
  }

  /**
   * @notice Updates the local blacklist and clears the whitelist flag when blocking an entity.
   * @param entity The address whose blacklist status is being updated.
   * @param status True to blacklist the entity, false to remove it from the blacklist.
   * @dev Only callable by the admin. Removing a blacklist entry does not restore an earlier whitelist grant.
   */
  function setBlacklistStatus(address entity, bool status) external {
    if (msg.sender != admin) revert NotAdmin(msg.sender);
    if (blacklist[entity] == status) return;

    blacklist[entity] = status;
    if (status) _setWhitelistStatus(entity, false);
    emit Blacklist(entity, status);
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
   * @dev Only the admin can update grants. Blacklisted entities always have a false whitelist flag.
   */
  function setWhitelistStatus(address entity, bool status) external {
    if (msg.sender != admin) revert NotAdmin(msg.sender);
    _setWhitelistStatus(entity, status && !blacklist[entity]);
  }

  /// @notice Stores a whitelist update and emits {Whitelist} only when the flag changes.
  /// @param entity The address whose whitelist status is being updated.
  /// @param status The new stored whitelist flag.
  function _setWhitelistStatus(address entity, bool status) private {
    if (whitelist[entity] == status) return;
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