require("hardhat/config");

const fs = require("fs");
const Module = require("module");
const os = require("os");
const path = require("path");
const { spawn, spawnSync } = require("child_process");
const vm = require("vm");
const { rejects } = require("assert");
const { expect } = require("chai");
const { ethers } = require("ethers");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");
const addresses = require("../../utils/addresses");

const REPO_ROOT = path.resolve(__dirname, "../..");
const HARDHAT_BIN = path.join(REPO_ROOT, "node_modules", ".bin", "hardhat");
const ANVIL_BIN = process.env.ANVIL_BIN || "anvil";
const ANVIL_PORT = 8545;
const ANVIL_URL = `http://127.0.0.1:${ANVIL_PORT}`;
const FORK_NETWORK = "mainnetFork";
// Includes the current blueprint and the factory-created Axiom, Sentinel and Bedrock vaults.
const FORK_BLOCK = 26025215;
const FORK_URL =
  process.env.MAINNET_FORK_URL ||
  (process.env.ALCHEMY_API_KEY ? `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}` : "") ||
  (process.env.INFURA_API_KEY ? `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}` : "");

const EXPECTED_PLAN_KEYS = [
  "chainId",
  "kind",
  "operationId",
  "payloads",
  "predecessor",
  "salt",
  "targets",
  "timelock",
  "values",
  "version",
].sort();

const PROXY_ADMIN_ABI = [
  "function upgrade(address proxy, address implementation)",
];

const TIMELOCK_ABI = [
  "function hashOperationBatch(address[] targets, uint256[] values, bytes[] payloads, bytes32 predecessor, bytes32 salt) view returns (bytes32)",
  "function isOperation(bytes32 id) view returns (bool)",
  "function isOperationPending(bytes32 id) view returns (bool)",
  "function getTimestamp(bytes32 id) view returns (uint256)",
  "function getMinDelay() view returns (uint256)",
  "function executeBatch(address[] targets, uint256[] values, bytes[] payloads, bytes32 predecessor, bytes32 salt)",
];

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const normalizeAddress = (value) => ethers.utils.getAddress(value);

const getPlanPath = () =>
  path.join(os.tmpdir(), `cv-upgrade-plan-${Date.now()}-${Math.random().toString(16).slice(2)}.json`);

const decodeUpgrades = (plan) => {
  const proxyAdminInterface = new ethers.utils.Interface(PROXY_ADMIN_ABI);
  return plan.payloads.map((payload) => {
    const [proxyAddress, newImplementation] = proxyAdminInterface.decodeFunctionData("upgrade", payload);
    return {
      proxyAddress: normalizeAddress(proxyAddress),
      newImplementation: normalizeAddress(newImplementation),
    };
  });
};

const loadTaskInternals = (runtimeEthers = ethers) => {
  const taskPath = path.join(REPO_ROOT, "tasks", "tranches-utils.js");
  const source = `${fs.readFileSync(taskPath, "utf8")}
module.exports = {
  CV_DEFAULT_BLUEPRINT_CDO_NAME,
  assertCvUpgradeReady,
  assertCvUpgradePlanReady,
  buildCvUpgradePlan,
  getCreditVaultUpgradeBlueprintTarget,
  getCreditVaultUpgradeTarget,
  getRequestedCvUpgradeComponents,
};
`;
  const taskRequire = Module.createRequire(taskPath);
  const chain = {
    addParam: () => chain,
    addOptionalParam: () => chain,
    setAction: () => chain,
  };
  const sandbox = {
    __dirname: path.dirname(taskPath),
    __filename: taskPath,
    console,
    ethers: runtimeEthers,
    module: { exports: {} },
    process,
    require: (id) => id === "hardhat/config" ? {} : taskRequire(id),
    task: () => chain,
    subtask: () => chain,
  };

  vm.runInNewContext(source, sandbox, { filename: taskPath });
  return sandbox.module.exports;
};

const runScheduleTask = ({ cdoNames, components, planPath, expectFailure = false }) => {
  const result = spawnSync(
    HARDHAT_BIN,
    [
      "schedule-cv-upgrades-timelock",
      "--network",
      FORK_NETWORK,
      "--cdonames",
      cdoNames,
      "--components",
      components,
      "--out",
      planPath,
    ],
    {
      cwd: REPO_ROOT,
      encoding: "utf8",
      env: {
        ...process.env,
        FORCE_COLOR: "0",
      },
      maxBuffer: 20 * 1024 * 1024,
    }
  );

  const output = `${result.stdout || ""}${result.stderr || ""}`;
  if (expectFailure) {
    expect(result.status, output).to.not.equal(0);
    return output;
  }

  expect(result.status, output).to.equal(0);
  return output;
};

const waitForRpc = async (provider, anvilState) => {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) {
    try {
      await provider.getBlockNumber();
      return;
    } catch (err) {
      await wait(250);
    }
  }
  throw new Error(`Timed out waiting for anvil fork\n${anvilState.logs}`);
};

const stopProcess = async (child) => {
  if (!child || child.exitCode !== null) {
    return;
  }

  await new Promise((resolve) => {
    const timeout = setTimeout(() => {
      if (child.exitCode === null) {
        child.kill("SIGKILL");
      }
    }, 5000);

    child.once("exit", () => {
      clearTimeout(timeout);
      resolve();
    });

    child.kill("SIGTERM");
  });
};

describe("credit vault upgrade task helpers", function () {
  const hreLike = {
    network: {
      name: "mainnet",
      config: {
        chainId: 1,
      },
    },
  };

  it("accepts revolving as the programmable borrower component key", function () {
    const { getRequestedCvUpgradeComponents } = loadTaskInternals();

    expect(getRequestedCvUpgradeComponents("strategy,revolving,cdo")).to.deep.equal([
      "strategy",
      "cdo",
      "revolving",
    ]);
  });

  it("resolves revolving to the programmable borrower proxy", async function () {
    const { getCreditVaultUpgradeTarget } = loadTaskInternals();

    const target = await getCreditVaultUpgradeTarget(
      hreLike,
      addresses.deployTokens,
      addresses.CDOs,
      "creditrevolvingearnifiusdc",
      "revolving"
    );

    expect(target).to.include({
      cdoName: "creditrevolvingearnifiusdc",
      component: "revolving",
      contractName: "contracts/strategies/idle/ProgrammableBorrower.sol:ProgrammableBorrower",
    });
    expect(normalizeAddress(target.proxyAddress)).to.equal(
      normalizeAddress(addresses.CDOs.creditrevolvingearnifiusdc.programmableBorrower)
    );
  });

  it("uses the revolving credit vault blueprint as the default implementation source", function () {
    const { CV_DEFAULT_BLUEPRINT_CDO_NAME } = loadTaskInternals();

    expect(CV_DEFAULT_BLUEPRINT_CDO_NAME).to.equal("creditrevolvingblueprintusdc");
  });

  it("resolves implementation source proxies from the selected blueprint", async function () {
    const { getCreditVaultUpgradeBlueprintTarget } = loadTaskInternals();

    const target = await getCreditVaultUpgradeBlueprintTarget(
      hreLike,
      addresses.deployTokens,
      addresses.CDOs,
      "creditrevolvingblueprintusdc",
      "revolving"
    );

    expect(target).to.include({
      cdoName: "creditrevolvingblueprintusdc",
      component: "revolving",
      contractName: "contracts/strategies/idle/ProgrammableBorrower.sol:ProgrammableBorrower",
    });
    expect(normalizeAddress(target.proxyAddress)).to.equal(
      normalizeAddress(addresses.CDOs.creditrevolvingblueprintusdc.programmableBorrower)
    );
  });

  it("returns null for missing optional components so the caller can skip them", async function () {
    const { getCreditVaultUpgradeTarget } = loadTaskInternals();

    const target = await getCreditVaultUpgradeTarget(
      hreLike,
      addresses.deployTokens,
      addresses.CDOs,
      "creditgauntlettestusdc",
      "revolving"
    );

    expect(target).to.equal(null);
  });

  // These live factory deployments intentionally have no deployment recipes.
  const factoryNames = ["creditaxiomwbtc", "creditbedrockstrategiesusdc", "creditsentinelusdusdc"];
  const getFactoryPlanContext = (prefunded = false, probeError) => {
    const blueprint = addresses.CDOs.creditrevolvingblueprintusdc;
    const admin = addresses.CDOs.creditaxiomwbtc.proxyAdmin;
    const timelockAddress = addresses.IdleTokens.mainnet.timelock;
    const oldImplementation = "0x0000000000000000000000000000000000000010";
    const newImplementations = {
      [blueprint.strategy.toLowerCase()]: "0x0000000000000000000000000000000000000011",
      [blueprint.cdoAddr.toLowerCase()]: "0x0000000000000000000000000000000000000012",
      [blueprint.queue.toLowerCase()]: "0x0000000000000000000000000000000000000013",
    };
    const adminSlot = ethers.utils.hexZeroPad(
      ethers.BigNumber.from(ethers.utils.id("eip1967.proxy.admin")).sub(1).toHexString(), 32
    );
    const runtimeEthers = {
      ...ethers,
      provider: {
        getNetwork: async () => ({ chainId: 1 }),
        send: async (method, [proxy, slot]) => {
          expect(method).to.equal("eth_getStorageAt");
          const value = slot === adminSlot ? admin : newImplementations[proxy.toLowerCase()] || oldImplementation;
          return ethers.utils.hexZeroPad(value, 32);
        },
      },
      getContractAt: async (_abi, proxy) => {
        if (normalizeAddress(proxy) === normalizeAddress(admin)) {
          return { owner: async () => timelockAddress, interface: new ethers.utils.Interface(PROXY_ADMIN_ABI) };
        }
        if (factoryNames.some(name => addresses.CDOs[name].strategy === proxy)) {
          return { defaultRecoveryInitialized: async () => true };
        }
        return {
          epochQueue: async () => {
            if (prefunded) return ethers.constants.AddressZero;
            throw probeError || Object.assign(new Error("missing epochQueue selector"), { code: "CALL_EXCEPTION", data: "0x" });
          },
        };
      },
    };
    return {
      runtimeEthers,
      runtime: { ...hreLike, ethers: runtimeEthers },
      options: {
        cdoNames: factoryNames,
        components: ["strategy", "cdo", "queue"],
        blueprintName: "creditrevolvingblueprintusdc",
        timelock: {
          address: timelockAddress,
          getMinDelay: async () => ethers.BigNumber.from(86400),
          hashOperationBatch: async (...args) => ethers.utils.keccak256(ethers.utils.defaultAbiCoder.encode(
            ["address[]", "uint256[]", "bytes[]", "bytes32", "bytes32"], args
          )),
        },
      },
    };
  };

  it("builds strategy-first batches for Axiom, Bedrock and Sentinel without deployTokens entries", async function () {
    for (const name of factoryNames) expect(addresses.deployTokens[name]).to.equal(undefined);
    const { runtimeEthers, runtime, options } = getFactoryPlanContext();
    const { buildCvUpgradePlan } = loadTaskInternals(runtimeEthers);
    const { plan } = await buildCvUpgradePlan(runtime, options);
    const axiom = addresses.CDOs.creditaxiomwbtc;
    const bedrock = addresses.CDOs.creditbedrockstrategiesusdc;
    const sentinel = addresses.CDOs.creditsentinelusdusdc;
    const upgrades = decodeUpgrades(plan);

    expect(upgrades.map(row => row.proxyAddress)).to.deep.equal([
      axiom.strategy, axiom.cdoAddr, axiom.queue,
      bedrock.strategy, bedrock.cdoAddr,
      sentinel.strategy, sentinel.cdoAddr, sentinel.queue,
    ].map(normalizeAddress));
    expect(upgrades.map(row => row.newImplementation)).to.deep.equal([
      "0x0000000000000000000000000000000000000011",
      "0x0000000000000000000000000000000000000012",
      "0x0000000000000000000000000000000000000013",
      "0x0000000000000000000000000000000000000011",
      "0x0000000000000000000000000000000000000012",
      "0x0000000000000000000000000000000000000011",
      "0x0000000000000000000000000000000000000012",
      "0x0000000000000000000000000000000000000013",
    ]);
  });

  it("rejects a standard blueprint for a factory prefunded CDO even with an unset queue", async function () {
    const { runtimeEthers, runtime, options } = getFactoryPlanContext(true);
    const { buildCvUpgradePlan } = loadTaskInternals(runtimeEthers);

    await rejects(buildCvUpgradePlan(runtime, options), /does not match creditaxiomwbtc\/cdo contract .*IdleCDOEpochVariantPrefunded/);
  });

  it("builds the Bedrock plan when Hardhat wraps the empty selector revert in a ProviderError", async function () {
    // Hardhat's live HTTP provider includes the JSON-RPC error; Anvil may return only empty data.
    const rpcError = Object.assign(new Error("execution reverted"), { name: "ProviderError", code: 3, _isProviderError: true });
    const probeError = Object.assign(new Error("missing revert data in call exception"), {
      code: "CALL_EXCEPTION", data: "0x", error: rpcError,
    });
    const { runtimeEthers, runtime, options } = getFactoryPlanContext(false, probeError);
    options.cdoNames = ["creditbedrockstrategiesusdc"];
    options.components = ["strategy", "cdo"];
    const { buildCvUpgradePlan } = loadTaskInternals(runtimeEthers);
    const { plan } = await buildCvUpgradePlan(runtime, options);
    const bedrock = addresses.CDOs.creditbedrockstrategiesusdc;

    expect(decodeUpgrades(plan).map(row => row.proxyAddress)).to.deep.equal([
      bedrock.strategy, bedrock.cdoAddr,
    ].map(normalizeAddress));
  });

  it("resolves prefunded blueprint types without a deployment recipe", async function () {
    const { runtime } = getFactoryPlanContext(true);
    const { getCreditVaultUpgradeBlueprintTarget } = loadTaskInternals();
    const target = await getCreditVaultUpgradeBlueprintTarget(runtime, {}, addresses.CDOs, "creditrevolvingblueprintusdc", "cdo");

    expect(target.contractName).to.equal("contracts/IdleCDOEpochVariantPrefunded.sol:IdleCDOEpochVariantPrefunded");
  });

  it("preserves explicitly configured CDO variants", async function () {
    const { getCreditVaultUpgradeTarget } = loadTaskInternals();
    const cdoVariant = "contracts/IdleCDOEpochVariantPrefunded.sol:IdleCDOEpochVariantPrefunded";
    const target = await getCreditVaultUpgradeTarget(
      hreLike, { factory: { cdoVariant } }, { factory: addresses.CDOs.creditaxiomwbtc }, "factory", "cdo"
    );

    expect(target.contractName).to.equal(cdoVariant);
  });

  it("does not classify RPC failures or nonempty reverts as standard factory CDOs", async function () {
    const { getCreditVaultUpgradeTarget } = loadTaskInternals();
    for (const fields of [
      { code: "NETWORK_ERROR" },
      { code: "CALL_EXCEPTION", data: "0x", error: new Error("RPC unavailable") },
      { code: "CALL_EXCEPTION", data: "0x", error: { code: 3, message: "execution reverted", data: "0x12345678" } },
      { code: "CALL_EXCEPTION", data: "0x", error: { code: 3, message: "RPC unavailable" } },
      { code: "CALL_EXCEPTION", data: "0x12345678" },
    ]) {
      const failure = Object.assign(new Error("lookup failed"), fields);
      const runtime = {
        ...hreLike,
        ethers: { getContractAt: async () => ({ epochQueue: async () => { throw failure; } }) },
      };
      await rejects(
        getCreditVaultUpgradeTarget(runtime, {}, addresses.CDOs, "creditaxiomwbtc", "cdo"),
        error => error === failure
      );
    }
  });

  it("still rejects vaults missing from CDOs", async function () {
    const { getCreditVaultUpgradeTarget } = loadTaskInternals();
    await rejects(getCreditVaultUpgradeTarget(hreLike, {}, {}, "missing", "cdo"), /Missing config for missing/);
  });

  it("applies the same clean-state preflight to timelock plans", async function () {
    const { assertCvUpgradeReady } = loadTaskInternals();
    const trackedCdo = {
      cdoAddr: "0x0000000000000000000000000000000000000002",
      strategy: "0x0000000000000000000000000000000000000001",
    };
    const hreWithPendingInstant = {
      ethers: {
        getContractAt: async () => ({
          defaultRecoveryInitialized: async () => false,
          pendingInstantWithdraws: async () => ethers.BigNumber.from(1),
          pendingWithdraws: async () => ethers.BigNumber.from(0),
        }),
      },
    };

    let error;
    try {
      await assertCvUpgradeReady(
        hreWithPendingInstant,
        trackedCdo,
        ["strategy", "cdo"],
        "test"
      );
    } catch (caught) {
      error = caught;
    }
    expect(error.message).to.include("pendingInstantWithdraws must be zero");
  });

  it("allows non-defaulted legacy normal pending state and rejects it after default", async function () {
    const { assertCvUpgradeReady } = loadTaskInternals();
    const trackedCdo = {
      cdoAddr: "0x0000000000000000000000000000000000000002",
      strategy: "0x0000000000000000000000000000000000000001",
    };
    let isDefaulted = false;
    const hreWithPendingNormal = {
      ethers: {
        getContractAt: async (_abi, address) => {
          if (normalizeAddress(address) === normalizeAddress(trackedCdo.strategy)) {
            return {
              defaultRecoveryInitialized: async () => false,
              pendingInstantWithdraws: async () => ethers.BigNumber.from(0),
              pendingWithdraws: async () => ethers.BigNumber.from(1),
            };
          }
          return {
            defaulted: async () => isDefaulted,
            epochEndDate: async () => ethers.BigNumber.from(1),
          };
        },
      },
    };

    await assertCvUpgradeReady(
      hreWithPendingNormal,
      trackedCdo,
      ["strategy", "cdo"],
      "test"
    );

    isDefaulted = true;
    let error;
    try {
      await assertCvUpgradeReady(
        hreWithPendingNormal,
        trackedCdo,
        ["strategy", "cdo"],
        "test"
      );
    } catch (caught) {
      error = caught;
    }
    expect(error.message).to.include("cannot upgrade legacy pendingWithdraws after borrower default");
  });

  it("requires selecting the strategy with a CDO upgrade", async function () {
    const { assertCvUpgradeReady } = loadTaskInternals();
    const trackedCdo = {
      cdoAddr: "0x0000000000000000000000000000000000000002",
      strategy: "0x0000000000000000000000000000000000000001",
    };
    let error;
    try {
      await assertCvUpgradeReady(
        {
          ethers: {
            getContractAt: async () => ({
              defaultRecoveryInitialized: async () => true,
            }),
          },
        },
        trackedCdo,
        ["cdo"],
        "test"
      );
    } catch (caught) {
      error = caught;
    }
    expect(error.message).to.include("select the strategy with the CDO");
  });

  it("rejects a prefunded queue-only timelock upgrade", async function () {
    const { assertCvUpgradeReady } = loadTaskInternals();
    const trackedCdo = {
      cdoAddr: "0x0000000000000000000000000000000000000002",
      strategy: "0x0000000000000000000000000000000000000001",
      queue: "0x0000000000000000000000000000000000000003",
    };
    const hreWithPrefundedQueue = {
      ethers: {
        getContractAt: async () => ({
          epochQueue: async () => trackedCdo.queue,
        }),
      },
    };

    let error;
    try {
      await assertCvUpgradeReady(
        hreWithPrefundedQueue,
        trackedCdo,
        ["queue"],
        "test"
      );
    } catch (caught) {
      error = caught;
    }
    expect(error.message).to.include("prefunded queue upgrade requires the CDO");
  });

  it("rechecks clean state from the saved plan immediately before execution", async function () {
    const { assertCvUpgradePlanReady } = loadTaskInternals();
    const trackedCdo = addresses.CDOs.creditgauntlettestusdc;
    const proxyAdminInterface = new ethers.utils.Interface(PROXY_ADMIN_ABI);
    const newImplementation = "0x0000000000000000000000000000000000000009";
    const plan = {
      targets: [trackedCdo.proxyAdmin, trackedCdo.proxyAdmin],
      payloads: [
        proxyAdminInterface.encodeFunctionData("upgrade", [trackedCdo.strategy, newImplementation]),
        proxyAdminInterface.encodeFunctionData("upgrade", [trackedCdo.cdoAddr, newImplementation]),
      ],
    };
    const hreWithDirtyState = {
      network: hreLike.network,
      ethers: {
        getContractAt: async (_abi, address) => {
          if (normalizeAddress(address) === normalizeAddress(trackedCdo.strategy)) {
            return {
              defaultRecoveryInitialized: async () => false,
              pendingInstantWithdraws: async () => ethers.BigNumber.from(1),
              pendingWithdraws: async () => ethers.BigNumber.from(0),
            };
          }
          throw new Error(`unexpected contract ${address}`);
        },
      },
    };

    let error;
    try {
      await assertCvUpgradePlanReady(hreWithDirtyState, plan);
    } catch (caught) {
      error = caught;
    }
    expect(error.message).to.include("pendingInstantWithdraws must be zero");
  });

  it("rejects a saved prefunded queue-only plan immediately before execution", async function () {
    const { assertCvUpgradePlanReady } = loadTaskInternals();
    const trackedCdo = addresses.CDOs.creditgauntlettestusdc;
    const proxyAdminInterface = new ethers.utils.Interface(PROXY_ADMIN_ABI);
    const plan = {
      targets: [trackedCdo.proxyAdmin],
      payloads: [
        proxyAdminInterface.encodeFunctionData("upgrade", [
          trackedCdo.queue,
          "0x0000000000000000000000000000000000000009",
        ]),
      ],
    };

    let error;
    try {
      await assertCvUpgradePlanReady(
        {
          network: hreLike.network,
          ethers: {
            getContractAt: async () => ({
              epochQueue: async () => trackedCdo.queue,
            }),
          },
        },
        plan
      );
    } catch (caught) {
      error = caught;
    }
    expect(error.message).to.include("prefunded queue upgrade requires the CDO");
  });

  it("rejects a saved plan whose proxy disappeared from network config", async function () {
    const { assertCvUpgradePlanReady } = loadTaskInternals();
    const proxyAdminInterface = new ethers.utils.Interface(PROXY_ADMIN_ABI);
    const missingProxy = "0x0000000000000000000000000000000000000008";
    const newImplementation = "0x0000000000000000000000000000000000000009";
    const plan = {
      targets: ["0x0000000000000000000000000000000000000007"],
      payloads: [
        proxyAdminInterface.encodeFunctionData("upgrade", [missingProxy, newImplementation]),
      ],
    };

    let error;
    try {
      await assertCvUpgradePlanReady(
        {
          network: hreLike.network,
          ethers: {
            getContractAt: async () => {
              throw new Error("unexpected state lookup");
            },
          },
        },
        plan
      );
    } catch (caught) {
      error = caught;
    }
    expect(error.message).to.include("missing from the current network config");
  });
});

describe("schedule-cv-upgrades-timelock integration", function () {
  this.timeout(0);

  let anvil;
  let provider;
  let snapshotId;
  let planPath;
  const anvilState = { logs: "" };

  before(async function () {
    if (!FORK_URL) {
      this.skip();
    }

    anvil = spawn(
      ANVIL_BIN,
      [
        "--fork-url",
        FORK_URL,
        "--fork-block-number",
        `${FORK_BLOCK}`,
        "--chain-id",
        "1",
        "--port",
        `${ANVIL_PORT}`,
      ],
      {
        cwd: REPO_ROOT,
        stdio: ["ignore", "pipe", "pipe"],
      }
    );

    anvil.stdout.on("data", (chunk) => {
      anvilState.logs += chunk.toString();
    });
    anvil.stderr.on("data", (chunk) => {
      anvilState.logs += chunk.toString();
    });

    provider = new ethers.providers.JsonRpcProvider(ANVIL_URL);
    await waitForRpc(provider, anvilState);

    const compilation = spawnSync(HARDHAT_BIN, ["compile"], { cwd: REPO_ROOT, encoding: "utf8" });
    expect(compilation.status, `${compilation.stdout}${compilation.stderr}`).to.equal(0);

    // Upgrade only the fork's blueprint so scheduling always has distinct candidate implementations.
    const blueprint = addresses.CDOs.creditrevolvingblueprintusdc;
    const admin = new ethers.Contract(blueprint.proxyAdmin, ["function owner() view returns (address)", ...PROXY_ADMIN_ABI], provider);
    const owner = await admin.owner();
    await provider.send("anvil_impersonateAccount", [owner]);
    await provider.send("anvil_setBalance", [owner, "0x56BC75E2D63100000"]);
    const signer = provider.getSigner(owner);
    for (const [proxy, artifactPath] of [
      [blueprint.strategy, "contracts/strategies/idle/IdleCreditVault.sol/IdleCreditVault.json"],
      [blueprint.cdoAddr, "contracts/IdleCDOEpochVariant.sol/IdleCDOEpochVariant.json"],
      [blueprint.queue, "contracts/IdleCDOEpochQueue.sol/IdleCDOEpochQueue.json"],
      [blueprint.programmableBorrower, "contracts/strategies/idle/ProgrammableBorrower.sol/ProgrammableBorrower.json"],
    ]) {
      const artifact = JSON.parse(fs.readFileSync(path.join(REPO_ROOT, "artifacts", artifactPath), "utf8"));
      const implementation = await new ethers.ContractFactory(artifact.abi, artifact.bytecode, signer).deploy();
      await implementation.deployed();
      await (await admin.connect(signer).upgrade(proxy, implementation.address)).wait();
    }
    snapshotId = await provider.send("evm_snapshot", []);
  });

  afterEach(async function () {
    if (planPath && fs.existsSync(planPath)) {
      fs.rmSync(planPath);
    }
    planPath = null;

    if (provider && snapshotId) {
      await provider.send("evm_revert", [snapshotId]);
      snapshotId = await provider.send("evm_snapshot", []);
    }
  });

  after(async function () {
    await stopProcess(anvil);
  });

  it("schedules a real strategy-first upgrade batch with plain upgrade calls", async function () {
    planPath = getPlanPath();

    runScheduleTask({
      cdoNames: "creditgauntlettestusdc",
      components: "cdo,strategy",
      planPath,
    });

    const plan = JSON.parse(fs.readFileSync(planPath, "utf8"));
    const cdoConfig = addresses.CDOs.creditgauntlettestusdc;
    const timelock = new ethers.Contract(plan.timelock, TIMELOCK_ABI, provider);

    expect(Object.keys(plan).sort()).to.deep.equal(EXPECTED_PLAN_KEYS);
    expect(plan.kind).to.equal("credit-vault-upgrade-batch");
    expect(plan.version).to.equal(1);
    expect(plan.chainId).to.equal("1");
    expect(normalizeAddress(plan.timelock)).to.equal(normalizeAddress(addresses.IdleTokens.mainnet.timelock));
    expect(plan.predecessor).to.equal(ethers.constants.HashZero);
    expect(plan.salt).to.equal(ethers.constants.HashZero);
    expect(plan.targets.map(normalizeAddress)).to.deep.equal([
      cdoConfig.proxyAdmin,
      cdoConfig.proxyAdmin,
    ].map(normalizeAddress));
    expect(plan.values).to.deep.equal([0, 0]);

    const decodedUpgrades = decodeUpgrades(plan);
    const blueprintConfig = addresses.CDOs.creditrevolvingblueprintusdc;
    const blueprintImplementations = [
      await getImplementationAddress(provider, blueprintConfig.strategy),
      await getImplementationAddress(provider, blueprintConfig.cdoAddr),
    ].map(normalizeAddress);
    expect(decodedUpgrades.map((item) => item.proxyAddress)).to.deep.equal([
      cdoConfig.strategy,
      cdoConfig.cdoAddr,
    ].map(normalizeAddress));

    const expectedOperationId = await timelock.hashOperationBatch(
      plan.targets,
      plan.values,
      plan.payloads,
      plan.predecessor,
      plan.salt
    );
    expect(plan.operationId).to.equal(expectedOperationId);
    expect(await timelock.isOperation(expectedOperationId)).to.equal(true);
    expect(await timelock.isOperationPending(expectedOperationId)).to.equal(true);
    expect(await timelock.getTimestamp(expectedOperationId)).to.not.equal(0);

    for (const upgrade of decodedUpgrades) {
      const currentImplementation = normalizeAddress(await getImplementationAddress(provider, upgrade.proxyAddress));
      expect(upgrade.newImplementation).to.not.equal(currentImplementation);
      expect(await provider.getCode(upgrade.newImplementation)).to.not.equal("0x");
    }
    expect(decodedUpgrades.map((item) => item.newImplementation)).to.deep.equal(blueprintImplementations);
  });

  it("reuses one new implementation per component when scheduling multiple stale vaults", async function () {
    planPath = getPlanPath();

    runScheduleTask({
      cdoNames: "creditgauntlettestusdc,creditm1capitalusdc",
      components: "cdo,strategy",
      planPath,
    });

    const plan = JSON.parse(fs.readFileSync(planPath, "utf8"));
    const timelock = new ethers.Contract(plan.timelock, TIMELOCK_ABI, provider);
    const decodedUpgrades = decodeUpgrades(plan);

    expect(plan.targets).to.have.length(4);
    expect(plan.values).to.deep.equal([0, 0, 0, 0]);
    expect(decodedUpgrades.map((item) => item.proxyAddress)).to.deep.equal([
      addresses.CDOs.creditgauntlettestusdc.strategy,
      addresses.CDOs.creditgauntlettestusdc.cdoAddr,
      addresses.CDOs.creditm1capitalusdc.strategy,
      addresses.CDOs.creditm1capitalusdc.cdoAddr,
    ].map(normalizeAddress));

    const uniqueNewImplementations = [...new Set(decodedUpgrades.map((item) => item.newImplementation))];
    expect(uniqueNewImplementations).to.have.length(2);

    const expectedOperationId = await timelock.hashOperationBatch(
      plan.targets,
      plan.values,
      plan.payloads,
      plan.predecessor,
      plan.salt
    );
    expect(plan.operationId).to.equal(expectedOperationId);
    expect(await timelock.isOperationPending(expectedOperationId)).to.equal(true);
  });

  it("schedules programmable borrower upgrades with the revolving component", async function () {
    planPath = getPlanPath();

    runScheduleTask({
      cdoNames: "creditrevolvingearnifiusdc",
      components: "revolving",
      planPath,
    });

    const plan = JSON.parse(fs.readFileSync(planPath, "utf8"));
    const cdoConfig = addresses.CDOs.creditrevolvingearnifiusdc;
    const decodedUpgrades = decodeUpgrades(plan);
    const blueprintConfig = addresses.CDOs.creditrevolvingblueprintusdc;
    const blueprintImplementation = normalizeAddress(await getImplementationAddress(provider, blueprintConfig.programmableBorrower));

    expect(plan.targets).to.have.length(1);
    expect(plan.values).to.deep.equal([0]);
    expect(plan.targets.map(normalizeAddress)).to.deep.equal([
      cdoConfig.proxyAdmin,
    ].map(normalizeAddress));
    expect(decodedUpgrades.map((item) => item.proxyAddress)).to.deep.equal([
      cdoConfig.programmableBorrower,
    ].map(normalizeAddress));
    expect(decodedUpgrades.map((item) => item.newImplementation)).to.deep.equal([
      blueprintImplementation,
    ]);
  });

  it("schedules and executes the Axiom, Bedrock and Sentinel batch without deployment recipes", async function () {
    const names = ["creditaxiomwbtc", "creditbedrockstrategiesusdc", "creditsentinelusdusdc"];
    for (const name of names) expect(addresses.deployTokens[name]).to.equal(undefined);
    planPath = getPlanPath();
    runScheduleTask({ cdoNames: names.join(","), components: "cdo,strategy,queue", planPath });

    const plan = JSON.parse(fs.readFileSync(planPath, "utf8"));
    const upgrades = decodeUpgrades(plan);
    expect(upgrades.map(row => row.proxyAddress)).to.deep.equal([
      addresses.CDOs.creditaxiomwbtc.strategy,
      addresses.CDOs.creditaxiomwbtc.cdoAddr,
      addresses.CDOs.creditaxiomwbtc.queue,
      addresses.CDOs.creditbedrockstrategiesusdc.strategy,
      addresses.CDOs.creditbedrockstrategiesusdc.cdoAddr,
      addresses.CDOs.creditsentinelusdusdc.strategy,
      addresses.CDOs.creditsentinelusdusdc.cdoAddr,
      addresses.CDOs.creditsentinelusdusdc.queue,
    ].map(normalizeAddress));

    // Execute only on Anvil, after the actual timelock delay, with its authorized executor.
    const executor = addresses.IdleTokens.mainnet.deployer;
    const timelock = new ethers.Contract(plan.timelock, TIMELOCK_ABI, provider.getSigner(executor));
    await provider.send("anvil_impersonateAccount", [executor]);
    await provider.send("evm_increaseTime", [(await timelock.getMinDelay()).toNumber() + 1]);
    await provider.send("evm_mine", []);
    await (await timelock.executeBatch(plan.targets, plan.values, plan.payloads, plan.predecessor, plan.salt)).wait();
    for (const upgrade of upgrades) {
      expect(normalizeAddress(await getImplementationAddress(provider, upgrade.proxyAddress))).to.equal(upgrade.newImplementation);
    }
  });

  it("logs and skips selected components that are not configured on a vault", async function () {
    planPath = getPlanPath();

    const output = runScheduleTask({
      cdoNames: "creditgauntlettestusdc,creditrevolvingearnifiusdc",
      components: "cdo,strategy,queue,revolving,writeoff",
      planPath,
    });

    expect(output).to.include("Skipping creditgauntlettestusdc / revolving: component not configured");
    expect(output).to.include("Skipping creditgauntlettestusdc / writeoff: component not configured");
    expect(output).to.include("Skipping creditrevolvingearnifiusdc / writeoff: component not configured");

    const plan = JSON.parse(fs.readFileSync(planPath, "utf8"));
    const decodedUpgrades = decodeUpgrades(plan);

    expect(plan.targets).to.have.length(7);
    expect(plan.values).to.deep.equal([0, 0, 0, 0, 0, 0, 0]);
    expect(decodedUpgrades.map((item) => item.proxyAddress)).to.deep.equal([
      addresses.CDOs.creditgauntlettestusdc.strategy,
      addresses.CDOs.creditgauntlettestusdc.cdoAddr,
      addresses.CDOs.creditgauntlettestusdc.queue,
      addresses.CDOs.creditrevolvingearnifiusdc.strategy,
      addresses.CDOs.creditrevolvingearnifiusdc.cdoAddr,
      addresses.CDOs.creditrevolvingearnifiusdc.queue,
      addresses.CDOs.creditrevolvingearnifiusdc.programmableBorrower,
    ].map(normalizeAddress));
  });
});
