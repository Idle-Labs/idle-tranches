// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../interfaces/ILidoOracle.sol";

contract MockLidoOracle is ILidoOracle {
    uint256 private postTotalPooledEther;
    uint256 private preTotalPooledEther;
    uint256 private timeElapsed;

    function getLastCompletedEpochId()
        external
        pure
        override
        returns (uint256)
    {
        return 1;
    }

    function getLastCompletedReportDelta()
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (postTotalPooledEther, preTotalPooledEther, timeElapsed);
    }

    function setLastCompletedEpochDelta(
        uint256 _postTotalPooledEther,
        uint256 _preTotalPooledEther,
        uint256 _timeElapsed
    ) public {
        postTotalPooledEther = _postTotalPooledEther;
        preTotalPooledEther = _preTotalPooledEther;
        timeElapsed = _timeElapsed;
    }
}
