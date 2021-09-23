// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./IdleCDO.sol";

contract IdleCDOCards is ERC721Enumerable {
    using Counters for Counters.Counter;
    using SafeERC20Upgradeable for IERC20Detailed;
    using SafeMath for uint256;

    uint256 public constant RATIO_PRECISION = 10**18;

    struct Card {
        uint256 exposure;
        uint256 amount;
    }

    IdleCDO internal idleCDO;
    Counters.Counter private _tokenIds;
    mapping(uint256 => Card) private _cards;

    constructor(address _idleCDOAddress) ERC721("IdleCDOCards", "ICC") {
        idleCDO = IdleCDO(_idleCDOAddress);
    }

    function mint(uint256 _risk, uint256 _amount) public returns (uint256) {
        // transfer amount to cards protocol
        _erc20().safeTransferFrom(msg.sender, address(this), _amount);

        // approve the amount to be spend on cdos tranches
        _erc20().approve(address(idleCDO), _amount);

        // calculate the amount to deposit in BB
        // proportional to risk and deposit
        uint256 depositBB = percentage(_risk, _amount);
        idleCDO.depositBB(depositBB);

        // calculate the amount to deposit in AA
        // inversely proportional to risk and deposit
        uint256 depositAA = _amount.sub(depositBB);
        idleCDO.depositAA(depositAA);

        // mint the Idle CDO card
        uint256 tokenId = _mint();
        _cards[tokenId] = Card(_risk, _amount);

        return tokenId;
    }

    function card(uint256 _tokenId) public view returns (Card memory) {
        return _cards[_tokenId];
    }

    function burn(uint256 _tokenId) public returns (uint256 toRedeem) {
        require(
            msg.sender == ownerOf(_tokenId),
            "burn of risk card that is not own"
        );

        _burn(_tokenId);

        Card memory _card = card(_tokenId);

        // calculate the amount to withdraw from AA tranche
        // inverse proportional to risk and withdraw
        uint256 amountAA = percentage(RATIO_PRECISION.sub(_card.exposure), _card.amount);
        uint256 toRedeemAA = amountAA > 0 ? idleCDO.withdrawAA(amountAA) : 0;

        // calculate the amount to withdraw from BB tranche
        // proportional to risk and withdraw
        uint256 amountBB = percentage(_card.exposure, _card.amount);
        uint256 toRedeemBB = amountBB > 0 ? idleCDO.withdrawBB(amountBB) : 0;

        // transfers everything withdrawn to its owner
        toRedeem = toRedeemAA.add(toRedeemBB);
        _erc20().safeTransfer(msg.sender, toRedeem);
    }

    function getApr(uint256 _exposure) public view returns (uint256) {
        // ratioAA = ratio of 1 - _exposure of the AA apr
        uint256 aprAA = idleCDO.getApr(idleCDO.AATranche());
        uint256 ratioAA = percentage(RATIO_PRECISION.sub(_exposure), aprAA);

        // ratioAA = ratio of _exposure of the AA apr
        uint256 aprBB = idleCDO.getApr(idleCDO.BBTranche());
        uint256 ratioBB = percentage(_exposure, aprBB);
        
        return ratioAA.add(ratioBB);
    }

    function percentage(uint256 _percentage, uint256 _amount)
        private
        pure
        returns (uint256)
    {
        require(
            _percentage < RATIO_PRECISION.add(1),
            "percentage should be between 0 and 1"
        );
        return _amount.mul(_percentage).div(RATIO_PRECISION);
    }

    function _mint() private returns (uint256) {
        _tokenIds.increment();

        uint256 newItemId = _tokenIds.current();
        _mint(msg.sender, newItemId);

        return newItemId;
    }

    function _erc20() private view returns (IERC20Detailed) {
        return IERC20Detailed(idleCDO.token());
    }
}
