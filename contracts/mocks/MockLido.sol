// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

contract MockLido is ERC20("Staked ETH", "stETH") {
    address private oracle;
    uint256 public fee = 1000;

    function getFee() external view returns (uint256) {
        return fee;
    }

    function setFee(uint256 _fee) external {
        fee = _fee;
    }

    function getOracle() external view returns (address) {
        return oracle;
    }

    function setOracle(address _oracle) public {
        oracle = _oracle;
    }

    function totalSupply() public view override returns (uint256) {
        return address(this).balance;
    }

    function submit(address)
        public
        payable
        returns (uint256 sharesAmount)
    {
        address sender = msg.sender;
        uint256 deposit = msg.value;
        require(deposit != 0, "ZERO_DEPOSIT");

        // totalControlledEther is 0: either the first-ever deposit or complete slashing
        // assume that shares correspond to Ether 1-to-1
        uint256 total = address(this).balance - deposit;
        sharesAmount = (total == 0)
            ? deposit
            : (deposit * totalSupply()) / total;
        _mint(sender, sharesAmount);
    }

    function getSharesByPooledEth(uint256 _ethAmount)
        public
        view
        returns (uint256)
    {
            uint256 totalPooledEther =  _getTotalPooledEther();
            if (totalPooledEther == 0) {
                return 0;
            } else {
                return (_ethAmount * totalSupply()) / totalPooledEther;
            }
    }

    // Simplified for testing
    function getTotalPooledEther() public view returns (uint256) {
        return _getTotalPooledEther();
    }

    // Simplified for testing
    function _getTotalPooledEther() internal view returns (uint256) {
        return address(this).balance;
    }

    // Simplified for testing
    function getPooledEthByShares(uint256 _sharesAmount)
        public
        view
        returns (uint256)
    {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) {
            return 0;
        } else {
            return (_sharesAmount * _getTotalPooledEther()) / totalShares;
        }
    }

    // For testing
    function getBeaconStat() 
        external 
        view 
        returns (
            uint256 depositedValidators,
            uint256 beaconValidators,
            uint256 beaconBalance
        )
    {

    }
}