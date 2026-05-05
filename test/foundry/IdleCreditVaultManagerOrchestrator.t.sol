// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IdleCreditVaultManagerOrchestrator} from "../../contracts/IdleCreditVaultManagerOrchestrator.sol";

contract MockOrchestratedCreditStrategy {
  address public manager;
  uint256 public unscaledApr;
  uint256 public apr;
  bool public canTransfer;

  constructor(address _manager) {
    manager = _manager;
  }

  function setManager(address _manager) external {
    manager = _manager;
  }

  function setAprs(uint256 _unscaledApr, uint256 _apr) external {
    require(msg.sender == manager, "not manager");
    unscaledApr = _unscaledApr;
    apr = _apr;
  }

  function setCanTransfer(bool _canTransfer) external {
    require(msg.sender == manager, "not manager");
    canTransfer = _canTransfer;
  }
}

contract MockOrchestratedCreditVault {
  address public strategy;
  address public manager;
  bool public isEpochRunning;
  bool public defaulted;
  bool public defaultOnStart;
  bool public defaultOnStop;
  bool public leaveRunningOnStop;
  uint256 public lastNewApr;
  uint256 public lastInterest;
  uint256 public lastDuration;
  uint256 public lastLossAmount;
  uint256 public epochDuration;
  uint256 public bufferPeriod;
  uint256 public instantWithdrawFundCalls;

  constructor(address _strategy, address _manager) {
    strategy = _strategy;
    manager = _manager;
  }

  modifier onlyManager() {
    require(msg.sender == manager, "not manager");
    _;
  }

  function setManager(address _manager) external {
    manager = _manager;
  }

  function setDefaultOnStart(bool _defaultOnStart) external {
    defaultOnStart = _defaultOnStart;
  }

  function setDefaultOnStop(bool _defaultOnStop) external {
    defaultOnStop = _defaultOnStop;
  }

  function setLeaveRunningOnStop(bool _leaveRunningOnStop) external {
    leaveRunningOnStop = _leaveRunningOnStop;
  }

  function startEpoch() external onlyManager {
    isEpochRunning = true;
    if (defaultOnStart) {
      defaulted = true;
    }
  }

  function stopEpochWithDuration(
    uint256 _newApr,
    uint256 _interest,
    uint256 _duration,
    uint256 _lossAmount
  ) external onlyManager {
    lastNewApr = _newApr;
    lastInterest = _interest;
    lastDuration = _duration;
    lastLossAmount = _lossAmount;
    if (!leaveRunningOnStop) {
      isEpochRunning = false;
    }
    if (defaultOnStop) {
      defaulted = true;
    }
  }

  function getInstantWithdrawFunds() external onlyManager {
    instantWithdrawFundCalls += 1;
  }

  function setEpochParams(uint256 _epochDuration, uint256 _bufferPeriod) external onlyManager {
    epochDuration = _epochDuration;
    bufferPeriod = _bufferPeriod;
  }
}

contract TestIdleCreditVaultManagerOrchestrator is Test {
  IdleCreditVaultManagerOrchestrator internal orchestrator;
  MockOrchestratedCreditVault internal cdoA;
  MockOrchestratedCreditVault internal cdoB;
  MockOrchestratedCreditStrategy internal strategyA;
  MockOrchestratedCreditStrategy internal strategyB;

  address internal operator = makeAddr("operator");
  address internal user = makeAddr("user");

  function setUp() public {
    orchestrator = _deployOrchestrator(operator);
    strategyA = new MockOrchestratedCreditStrategy(address(orchestrator));
    strategyB = new MockOrchestratedCreditStrategy(address(orchestrator));
    cdoA = new MockOrchestratedCreditVault(address(strategyA), address(orchestrator));
    cdoB = new MockOrchestratedCreditVault(address(strategyB), address(orchestrator));

    orchestrator.setCreditVaultAllowed(address(cdoA), true);
    orchestrator.setCreditVaultAllowed(address(cdoB), true);
  }

  function testStartEpochStartsAllVaultsAndChecksPostconditions() external {
    address[] memory cdos = new address[](2);
    cdos[0] = address(cdoA);
    cdos[1] = address(cdoB);

    vm.prank(operator);
    orchestrator.startEpoch(cdos);

    assertTrue(cdoA.isEpochRunning(), "cdo A should be running");
    assertTrue(cdoB.isEpochRunning(), "cdo B should be running");
  }

  function testStartEpochRevertsIfVaultDefaults() external {
    address[] memory cdos = new address[](1);
    cdos[0] = address(cdoA);
    cdoA.setDefaultOnStart(true);

    vm.expectRevert(IdleCreditVaultManagerOrchestrator.OrchestratorStartFailed.selector);
    vm.prank(operator);
    orchestrator.startEpoch(cdos);

    assertFalse(cdoA.isEpochRunning(), "state should roll back");
    assertFalse(cdoA.defaulted(), "default should roll back");
  }

  function testStopEpochWithDurationRevertsOnUnexpectedDefault() external {
    _start(address(cdoA));
    cdoA.setDefaultOnStop(true);

    IdleCreditVaultManagerOrchestrator.StopEpochWithDurationAction[] memory actions =
      new IdleCreditVaultManagerOrchestrator.StopEpochWithDurationAction[](1);
    actions[0] = IdleCreditVaultManagerOrchestrator.StopEpochWithDurationAction({
      cdo: address(cdoA),
      newApr: 10e18,
      interest: 0,
      duration: 30 days,
      loss: 0,
      allowDefault: false
    });

    vm.expectRevert(IdleCreditVaultManagerOrchestrator.OrchestratorDefaulted.selector);
    vm.prank(operator);
    orchestrator.stopEpochWithDuration(actions);

    assertTrue(cdoA.isEpochRunning(), "state should roll back");
    assertFalse(cdoA.defaulted(), "default should roll back");
  }

  function testStopEpochWithDurationAllowsExpectedDefault() external {
    _start(address(cdoA));
    cdoA.setDefaultOnStop(true);

    IdleCreditVaultManagerOrchestrator.StopEpochWithDurationAction[] memory actions =
      new IdleCreditVaultManagerOrchestrator.StopEpochWithDurationAction[](1);
    actions[0] = IdleCreditVaultManagerOrchestrator.StopEpochWithDurationAction({
      cdo: address(cdoA),
      newApr: 10e18,
      interest: 0,
      duration: 30 days,
      loss: 0,
      allowDefault: true
    });

    vm.prank(operator);
    orchestrator.stopEpochWithDuration(actions);

    assertFalse(cdoA.isEpochRunning(), "cdo should be stopped");
    assertTrue(cdoA.defaulted(), "cdo should be defaulted");
  }

  function testStopEpochWithDurationForwardsArgsAndChecksStopped() external {
    _start(address(cdoA));

    IdleCreditVaultManagerOrchestrator.StopEpochWithDurationAction[] memory actions =
      new IdleCreditVaultManagerOrchestrator.StopEpochWithDurationAction[](1);
    actions[0] = IdleCreditVaultManagerOrchestrator.StopEpochWithDurationAction({
      cdo: address(cdoA),
      newApr: 7e18,
      interest: 123,
      duration: 21 days,
      loss: 456,
      allowDefault: false
    });

    vm.prank(operator);
    orchestrator.stopEpochWithDuration(actions);

    assertFalse(cdoA.isEpochRunning(), "cdo should be stopped");
    assertFalse(cdoA.defaulted(), "cdo should not be defaulted");
    assertEq(cdoA.lastNewApr(), 7e18, "new APR");
    assertEq(cdoA.lastInterest(), 123, "interest");
    assertEq(cdoA.lastDuration(), 21 days, "duration");
    assertEq(cdoA.lastLossAmount(), 456, "loss amount");
  }

  function testAdminForwardsUseStrategyDerivedFromCdo() external {
    vm.startPrank(operator);
    orchestrator.setEpochParams(address(cdoA), 30 days, 5 days);
    orchestrator.getInstantWithdrawFunds(address(cdoA));
    orchestrator.setStrategyAprsRaw(address(cdoA), 8e18, 9e18);
    orchestrator.setCanTransfer(address(cdoA), true);
    vm.stopPrank();

    assertEq(cdoA.epochDuration(), 30 days, "epoch duration");
    assertEq(cdoA.bufferPeriod(), 5 days, "buffer period");
    assertEq(cdoA.instantWithdrawFundCalls(), 1, "instant withdraw calls");
    assertEq(strategyA.unscaledApr(), 8e18, "unscaled APR");
    assertEq(strategyA.apr(), 9e18, "raw APR");
    assertTrue(strategyA.canTransfer(), "can transfer");

    assertEq(strategyB.unscaledApr(), 0, "other strategy untouched");
    assertFalse(strategyB.canTransfer(), "other transfer flag untouched");
  }

  function testNonOperatorCannotOperate() external {
    address[] memory cdos = new address[](1);
    cdos[0] = address(cdoA);

    vm.expectRevert(IdleCreditVaultManagerOrchestrator.OrchestratorNotOperator.selector);
    vm.prank(user);
    orchestrator.startEpoch(cdos);
  }

  function testCannotReinitialize() external {
    vm.expectRevert(bytes("Initializable: contract is already initialized"));
    orchestrator.initialize(operator);
  }

  function _start(address _cdo) internal {
    address[] memory cdos = new address[](1);
    cdos[0] = _cdo;
    vm.prank(operator);
    orchestrator.startEpoch(cdos);
  }

  function _deployOrchestrator(address _operator) internal returns (IdleCreditVaultManagerOrchestrator) {
    IdleCreditVaultManagerOrchestrator implementation = new IdleCreditVaultManagerOrchestrator();
    ERC1967Proxy proxy = new ERC1967Proxy(
      address(implementation),
      abi.encodeWithSelector(IdleCreditVaultManagerOrchestrator.initialize.selector, _operator)
    );
    return IdleCreditVaultManagerOrchestrator(address(proxy));
  }
}
