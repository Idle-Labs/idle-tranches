// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "../../contracts/strategies/euler/IdleEulerStakingStrategy.sol";
import "./TestIdleCDOBase.sol";

contract TestIdleEulerStakingStrategy is TestIdleCDOBase {
    using stdStorage for StdStorage;

    function _deployStrategy(address _owner) internal override returns (address _strategy, address _underlying) {
        address lendingToken = 0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716; // eUSDC
        _underlying = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address eulerMain = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
        // https://github.com/euler-xyz/euler-staking/blob/801634ba8753f3d30e68eaf85afa8c104d39b3b8/addresses/euler-staking-addresses-mainnet.json
        address stakingRewards = 0xE5aFE81e63f0A52a3a03B922b30f73B8ce74D570;
        strategy = new IdleEulerStakingStrategy();
        _strategy = address(strategy);
        stdstore.target(_strategy).sig(strategy.token.selector).checked_write(address(0));
        IdleEulerStakingStrategy(_strategy).initialize(lendingToken, _underlying, eulerMain, stakingRewards, _owner);

        vm.label(eulerMain, "euler");
        vm.label(stakingRewards, "stakingRewards");
    }

    function _postDeploy(address _cdo, address _owner) internal override {
        vm.prank(_owner);
        IdleEulerStakingStrategy(address(strategy)).setWhitelistedCDO(address(_cdo));
    }

    function testOnlyOwner() public override runOnForkingNetwork(MAINNET_CHIANID) {
        super.testOnlyOwner();

        vm.startPrank(address(0xbabe));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        IdleEulerStakingStrategy(address(strategy)).setReleaseBlocksPeriod(10);

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        IdleEulerStakingStrategy(address(strategy)).exitStaking();

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        IdleEulerStakingStrategy(address(strategy)).setStakingRewards(address(0x123));

        vm.stopPrank();
    }

    function testCantReinitialize() external override runOnForkingNetwork(MAINNET_CHIANID) {
        address lendingToken = 0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716; // eUSDC
        address _underlying = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address eulerMain = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
        address stakingRewards = 0xE5aFE81e63f0A52a3a03B922b30f73B8ce74D570;

        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        IdleEulerStakingStrategy(address(strategy)).initialize(
            lendingToken,
            _underlying,
            eulerMain,
            stakingRewards,
            owner
        );
    }
}
