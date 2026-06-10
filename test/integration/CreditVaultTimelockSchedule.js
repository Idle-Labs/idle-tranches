require("hardhat/config");

const fs = require("fs");
const Module = require("module");
const os = require("os");
const path = require("path");
const { spawn, spawnSync } = require("child_process");
const vm = require("vm");
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
// Fork after the latest credit-vault implementation deployments recorded in .openzeppelin/mainnet.json.
const FORK_BLOCK = 24600000;
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

const loadTaskInternals = () => {
  const taskPath = path.join(REPO_ROOT, "tasks", "tranches-utils.js");
  const source = `${fs.readFileSync(taskPath, "utf8")}
module.exports = {
  CV_DEFAULT_BLUEPRINT_CDO_NAME,
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
    ethers,
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
      "cdo",
      "strategy",
      "revolving",
    ]);
  });

  it("resolves revolving to the programmable borrower proxy", function () {
    const { getCreditVaultUpgradeTarget } = loadTaskInternals();

    const target = getCreditVaultUpgradeTarget(
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

  it("resolves implementation source proxies from the selected blueprint", function () {
    const { getCreditVaultUpgradeBlueprintTarget } = loadTaskInternals();

    const target = getCreditVaultUpgradeBlueprintTarget(
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

  it("returns null for missing optional components so the caller can skip them", function () {
    const { getCreditVaultUpgradeTarget } = loadTaskInternals();

    const target = getCreditVaultUpgradeTarget(
      hreLike,
      addresses.deployTokens,
      addresses.CDOs,
      "creditgauntlettestusdc",
      "revolving"
    );

    expect(target).to.equal(null);
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

  it("schedules a real cdo+strategy upgrade batch and writes the minimal plan", async function () {
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
      await getImplementationAddress(provider, blueprintConfig.cdoAddr),
      await getImplementationAddress(provider, blueprintConfig.strategy),
    ].map(normalizeAddress);
    expect(decodedUpgrades.map((item) => item.proxyAddress)).to.deep.equal([
      cdoConfig.cdoAddr,
      cdoConfig.strategy,
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
      cdoNames: "creditgauntlettestusdc,creditl1testusdc",
      components: "cdo,strategy",
      planPath,
    });

    const plan = JSON.parse(fs.readFileSync(planPath, "utf8"));
    const timelock = new ethers.Contract(plan.timelock, TIMELOCK_ABI, provider);
    const decodedUpgrades = decodeUpgrades(plan);

    expect(plan.targets).to.have.length(4);
    expect(plan.values).to.deep.equal([0, 0, 0, 0]);
    expect(decodedUpgrades.map((item) => item.proxyAddress)).to.deep.equal([
      addresses.CDOs.creditgauntlettestusdc.cdoAddr,
      addresses.CDOs.creditgauntlettestusdc.strategy,
      addresses.CDOs.creditl1testusdc.cdoAddr,
      addresses.CDOs.creditl1testusdc.strategy,
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
      addresses.CDOs.creditgauntlettestusdc.cdoAddr,
      addresses.CDOs.creditgauntlettestusdc.strategy,
      addresses.CDOs.creditgauntlettestusdc.queue,
      addresses.CDOs.creditrevolvingearnifiusdc.cdoAddr,
      addresses.CDOs.creditrevolvingearnifiusdc.strategy,
      addresses.CDOs.creditrevolvingearnifiusdc.queue,
      addresses.CDOs.creditrevolvingearnifiusdc.programmableBorrower,
    ].map(normalizeAddress));
  });
});
