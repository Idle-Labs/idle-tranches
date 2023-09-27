const { StandardMerkleTree } = require("@openzeppelin/merkle-tree");
const fs = require("fs");

/**
 * @name chainid
 */
task("chainid").setAction(async function ({ time }) {
  const chainId = await ethers.provider.send("eth_chainId");
  console.log("ChainId:", chainId);
});

/**
 * @name blocknumber
 */
task("blocknumber").setAction(async function ({ time }) {
  const blocknumber = await ethers.provider.getBlockNumber();
  console.log("Blocknumber:", blocknumber);
});

/**
 * @name blockinfo
 */
task("blockinfo").setAction(async function ({ time }) {
  const blocknumber = await ethers.provider.getBlockNumber();
  const block = await ethers.provider.getBlock(blocknumber);
  console.log("Latest block: ", block);
  console.log("Timestamp: ", block.timestamp);
  console.log("Number: ", blocknumber);
});

/**
 * @name accounts
 */
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();
  for (const account of accounts) {
    console.log(await account.getAddress());
  }
});

/**
 * @name increase-time
 * @param time
 */
task("increase-time")
  .addPositionalParam("time")
  .setAction(async function ({ time }) {
    await ethers.provider.send("evm_increaseTime", [Number(time)]);
    await run("blocknumber");
  });

/**
 * @name increase-time
 * @param time
 */
task("increase-time-mine")
  .addPositionalParam("time")
  .setAction(async function ({ time }) {
    await ethers.provider.send("evm_increaseTime", [Number(time)]);
    await run("mine");
    await run("blocknumber");
  });

/**
 * @name set-time
 * @param {Number} time
 */
task("set-time")
  .addPositionalParam("time")
  .setAction(async function ({ time }) {
    await ethers.provider.send("evm_setNextBlockTimestamp", [Number(time)]);
    await run("blocknumber");
  });

/**
 * @name advance-time
 * @param {Number} time
 */
task("set-time-mine")
  .addPositionalParam("time")
  .setAction(async function ({ time }) {
    await ethers.provider.send("evm_setNextBlockTimestamp", [Number(time)]);
    await run("mine");
    await run("blocknumber");
  });

/**
 * @name mine
 */
task("mine").setAction(async function () {
  await ethers.provider.send("evm_mine");
  await run("blocknumber");
});

/**
 * @name mine-multiple
 * * @param {Number} blocks
 */
task("mine-multiple")
  .addPositionalParam("blocks")
  .setAction(async function ({ blocks }) {
    await run("blocknumber");
    for (let index = 0; index < blocks; index++) {
      await ethers.provider.send("evm_mine");
    }
    await run("blocknumber");
  });

/**
* @name generate-merkle
* * @param {Number} blocks
*/
task("generate-merkle")
  .setAction(async function () {
    const file = fs.readFileSync("treeInput.csv", "utf8");
    const lines = file.trim().split('\n');
    const values = lines.map(line => line.split(',').map(item => item.trim()));
    const tree = StandardMerkleTree.of(values, ["address", "uint256"]);
    console.log('Merkle Root:', tree.root);
    fs.writeFileSync("tree1.json", JSON.stringify(tree.dump()));
  });
