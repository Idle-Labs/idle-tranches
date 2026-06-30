// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "forge-std/Vm.sol";

abstract contract CDOStorageReader {
  Vm internal constant CDO_VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

  uint256 internal constant CDO_READER_SLOT_REBALANCER = 210;
  uint256 internal constant CDO_READER_SLOT_WITHDRAW_FLAGS = 211;
  uint256 internal constant CDO_READER_SLOT_RELEASE_BLOCKS_PERIOD = 230;
  uint256 internal constant CDO_READER_OFFSET_ALLOW_AA_WITHDRAW = 20;
  uint256 internal constant CDO_READER_OFFSET_ALLOW_BB_WITHDRAW = 21;

  /// @notice Reads a full uint256 from a CDO storage slot.
  /// @param cdoAddress CDO address to inspect.
  /// @param cdoSlot Storage slot to read.
  /// @return slotValue Raw slot value converted to uint256.
  function _cdoUint256(address cdoAddress, uint256 cdoSlot) internal view returns (uint256 slotValue) {
    slotValue = uint256(CDO_VM.load(cdoAddress, bytes32(cdoSlot)));
  }

  /// @notice Reads an address from a CDO storage slot.
  /// @param cdoAddress CDO address to inspect.
  /// @param cdoSlot Storage slot to read.
  /// @param cdoOffset Byte offset within the slot.
  /// @return slotAddress Address stored at the requested slot offset.
  function _cdoAddress(address cdoAddress, uint256 cdoSlot, uint256 cdoOffset)
    internal
    view
    returns (address slotAddress)
  {
    slotAddress = address(uint160(_cdoUint256(cdoAddress, cdoSlot) >> (cdoOffset * 8)));
  }

  /// @notice Reads a bool from a CDO storage slot.
  /// @param cdoAddress CDO address to inspect.
  /// @param cdoSlot Storage slot to read.
  /// @param cdoOffset Byte offset within the slot.
  /// @return slotBool Bool stored at the requested slot offset.
  function _cdoBool(address cdoAddress, uint256 cdoSlot, uint256 cdoOffset)
    internal
    view
    returns (bool slotBool)
  {
    slotBool = ((_cdoUint256(cdoAddress, cdoSlot) >> (cdoOffset * 8)) & 0xff) != 0;
  }

  /// @notice Returns the CDO rebalancer from storage after its generated getter was removed.
  /// @param cdoAddress CDO address to inspect.
  /// @return cdoRebalancer Rebalancer address.
  function _cdoRebalancer(address cdoAddress) internal view returns (address cdoRebalancer) {
    cdoRebalancer = _cdoAddress(cdoAddress, CDO_READER_SLOT_REBALANCER, 0);
  }

  /// @notice Returns the CDO release blocks period from storage after its generated getter was removed.
  /// @param cdoAddress CDO address to inspect.
  /// @return cdoReleaseBlocksPeriod Release blocks period.
  function _cdoReleaseBlocksPeriod(address cdoAddress) internal view returns (uint256 cdoReleaseBlocksPeriod) {
    cdoReleaseBlocksPeriod = _cdoUint256(cdoAddress, CDO_READER_SLOT_RELEASE_BLOCKS_PERIOD);
  }

  /// @notice Returns the CDO AA withdraw flag from storage after its generated getter was removed.
  /// @param cdoAddress CDO address to inspect.
  /// @return cdoAllowAAWithdraw AA withdraw flag.
  function _cdoAllowAAWithdraw(address cdoAddress) internal view returns (bool cdoAllowAAWithdraw) {
    cdoAllowAAWithdraw = _cdoBool(
      cdoAddress,
      CDO_READER_SLOT_WITHDRAW_FLAGS,
      CDO_READER_OFFSET_ALLOW_AA_WITHDRAW
    );
  }

  /// @notice Returns the CDO BB withdraw flag from storage after its generated getter was removed.
  /// @param cdoAddress CDO address to inspect.
  /// @return cdoAllowBBWithdraw BB withdraw flag.
  function _cdoAllowBBWithdraw(address cdoAddress) internal view returns (bool cdoAllowBBWithdraw) {
    cdoAllowBBWithdraw = _cdoBool(
      cdoAddress,
      CDO_READER_SLOT_WITHDRAW_FLAGS,
      CDO_READER_OFFSET_ALLOW_BB_WITHDRAW
    );
  }
}
