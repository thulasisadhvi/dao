import { ethers, network } from "hardhat";

async function main() {
  // 1. Get Test Wallets
  const [deployer, user1] = await ethers.getSigners();
  console.log("----------------------------------------------------");
  console.log("🚀 Deploying contracts with account:", deployer.address);

  // 2. Deploy GovernanceStaking
  const Staking = await ethers.getContractFactory("GovernanceStaking");
  const staking = await Staking.deploy();
  await staking.deployed();
  console.log("✅ Staking Contract deployed to:", staking.address);

  // 3. Deploy TreasuryTimelock
  const Timelock = await ethers.getContractFactory("TreasuryTimelock");
  const timelock = await Timelock.deploy(deployer.address);
  await timelock.deployed();
  console.log("✅ Timelock Contract deployed to:", timelock.address);

  // 4. Deploy DAO_Governor
  const Governor = await ethers.getContractFactory("DAO_Governor");
  const governor = await Governor.deploy(staking.address, timelock.address);
  await governor.deployed();
  console.log("✅ Governor Contract deployed to:", governor.address);

  // 5. WIRE IT UP
  console.log("----------------------------------------------------");
  console.log("🔗 Wiring contracts together...");
  
  const tx = await timelock.setPendingAdmin(governor.address);
  await tx.wait();
  console.log("🔐 Timelock Admin transferred to Governor!");

  // 6. SEED DATA
  console.log("----------------------------------------------------");
  console.log("🌱 Seeding test data...");

  // A. Stake 2 ETH
  const stakeAmount = ethers.utils.parseEther("2.0"); 
  await staking.connect(user1).deposit({ value: stakeAmount });
  console.log(`   - User1 (${user1.address}) staked 2.0 ETH`);

  // B. Delegate
  await staking.connect(user1).delegate(user1.address);
  console.log("   - User1 delegated votes to self");

  // C. Mine block
  await network.provider.send("evm_mine", []);

  // D. Create Proposal
  const description = "Proposal #1: Grant 5 ETH to Marketing";
  await governor.connect(user1).propose(
      [timelock.address], 
      [0], 
      [""], 
      ["0x"], 
      description, 
      0 
  );
  console.log("   - User1 created Proposal #1");

  console.log("----------------------------------------------------");
  console.log("🎉 Deployment & Seeding Complete!");
  console.log("----------------------------------------------------");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});