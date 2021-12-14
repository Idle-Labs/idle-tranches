// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../../interfaces/IWETH.sol";
import "../../interfaces/IStETH.sol";
import "../../interfaces/IWstETH.sol";
import "../../IdleCDO.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @author massun-onibakuchi
/// @title LidoCDOTrancheGateway
/// @notice Helper contract for Idle Lido Tranche. This contract converts ETH/WETH to stETH, and deposit those in IdleCDOTranche
/// @dev This contract should not have any funds at the end of each tx.
contract LidoCDOTrancheGateway {
    using SafeERC20 for IERC20;

    address public immutable wethToken;
    address public immutable wstETH;
    address public immutable stETH;
    IdleCDO public immutable idleCDO;
    address public referral;

    constructor(
        address _wethToken,
        address _wstETH,
        address _stETH,
        IdleCDO _idleCDO,
        address _referral
    ) {
        require(_wethToken != address(0) && _wstETH != address(0) && _stETH != address(0) && address(_idleCDO) != address(0),"zero-address");
        wethToken = _wethToken;
        wstETH = _wstETH;
        stETH = _stETH;
        idleCDO = _idleCDO;
        referral = _referral;
    }

    function depositAAWithEth() public payable returns (uint256 minted) {
        uint256 shares = _mintStEth(msg.value);
        IERC20(stETH).safeApprove(address(idleCDO), shares);
        minted = _depositBehalf(idleCDO.depositAA, idleCDO.AATranche(), msg.sender, shares);
    }

    function depositBBWithEth() public payable returns (uint256 minted) {
        uint256 shares = _mintStEth(msg.value);
        IERC20(stETH).safeApprove(address(idleCDO), shares);
        minted = _depositBehalf(idleCDO.depositBB, idleCDO.BBTranche(), msg.sender, shares);
    }

    function depositAAWithEthToken(address token, uint256 amount) public returns (uint256 minted) {
        return _depositWithEthToken(idleCDO.depositAA, idleCDO.AATranche(), token, msg.sender, msg.sender, amount);
    }

    function depositBBWithEthToken(address token, uint256 amount) public returns (uint256 minted) {
        return _depositWithEthToken(idleCDO.depositBB, idleCDO.BBTranche(), token, msg.sender, msg.sender, amount);
    }

    function _depositWithEthToken(
        function(uint256) external returns (uint256) _depositFn,
        address _tranche,
        address _token,
        address _from,
        address _onBehalfOf,
        uint256 _amount
    ) internal returns (uint256 minted) {
        uint amtToDeposit;
        if (_token == wethToken) {
            IERC20(wethToken).safeTransferFrom(_from, address(this), _amount);
            IWETH(wethToken).withdraw(_amount);
            // mint stETH
            amtToDeposit = _mintStEth(address(this).balance);
        } else if (_token == stETH) {
            amtToDeposit = _amount;
            IERC20(stETH).safeTransferFrom(_from, address(this), _amount);
        } else {
            revert("invalid-token-address");
        }
        // deposit stETH to IdleCDO and mint tranche
        IERC20(stETH).safeApprove(address(idleCDO), amtToDeposit);
        minted = _depositBehalf(_depositFn, _tranche, _onBehalfOf, amtToDeposit);
    }

    function _depositBehalf(
        function(uint256) external returns (uint256) _depositFn,
        address _tranche,
        address _onBehalfOf,
        uint256 _amount
    ) private returns (uint256 minted) {
        minted = _depositFn(_amount);
        IERC20(_tranche).transfer(_onBehalfOf, minted);
    }

    function _mintStEth(uint256 _ethAmount) private returns (uint256 shares) {
        shares = IStETH(stETH).submit{ value: _ethAmount }(referral);
    }

    receive() external payable {
        require(msg.sender == wethToken, "only-weth");
    }
}
