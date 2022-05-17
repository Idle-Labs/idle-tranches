// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

interface IDeltaStrikeSelection {

    function getStrikePrice(uint256 expiryTimestamp, bool isPut) external view returns (uint256 newStrikePrice, uint256 newDelta);
    function getStrikePriceWithVol(uint256 expiryTimestamp, bool isPut, uint256 annualizedVol) external view returns (uint256 newStrikePrice, uint256 newDelta);

    function setDelta(uint256 newDelta) external;
    function setStep(uint256 newStep) external;
    
}
