import { expect } from "chai";
import { ethers } from "hardhat";
import { time, mine } from "@nomicfoundation/hardhat-network-helpers";
import { Contract } from "ethers";

describe("CryptoVentures DAO System", function () {
  let staking: Contract;
  let timelock: Contract;
  let governor: Contract;
  let deployer: any, user1: any;

  beforeEach(async function () {
    [deployer, user1] = await ethers.getSigners();

    // 1. Deploy Staking
    const Staking = await ethers.getContractFactory("GovernanceStaking");
    staking = await Staking.deploy();
    await staking.deployed();

    // 2. Deploy Timelock
    const Timelock = await ethers.getContractFactory("TreasuryTimelock");
    timelock = await Timelock.deploy(deployer.address);
    await timelock.deployed();

    // 3. Deploy Governor
    const Governor = await ethers.getContractFactory("DAO_Governor");
    governor = await Governor.deploy(staking.address, timelock.address);
    await governor.deployed();

    // 4. Transfer Timelock Admin to Governor
    await timelock.setPendingAdmin(governor.address);
  });

  it("Should allow staking and delegation", async function () {
    const stakeAmount = ethers.utils.parseEther("10");
    await staking.connect(user1).deposit({ value: stakeAmount });
    expect(await staking.stakeBalance(user1.address)).to.equal(stakeAmount);
    await staking.connect(user1).delegate(user1.address);
    
    // Mine 1 block to register the checkpoint
    await mine(1);
    const votes = await staking.getVotes(user1.address);
    expect(votes).to.be.gt(0);
  });

  it("Should execute a complete proposal lifecycle", async function () {
    // --- Setup ---
    const stakeAmount = ethers.utils.parseEther("5"); 
    await staking.connect(user1).deposit({ value: stakeAmount });
    await staking.connect(user1).delegate(user1.address);
    
    // Mine blocks to ensure votes are active
    await mine(5);

    // --- 1. Propose ---
    const description = "Proposal #1: Send Funds";
    const tx = await governor.connect(user1).propose(
      [timelock.address],
      [0],
      [""],
      ["0x"],
      description,
      0 // Type 0 = General
    );
    const receipt = await tx.wait();
    // @ts-ignore
    const event = receipt.events.find((e: any) => e.event === 'ProposalCreated');
    const proposalId = event.args.proposalId;

    // --- 2. Vote ---
    // Wait for Voting Delay
    await mine(2);
    
    await governor.connect(user1).castVote(proposalId, 1); // 1 = For

    // --- 3. Queue ---
    // Mine BLOCKS to pass the Voting Period (25000 blocks)
    await mine(25000); 
    
    await governor.connect(user1).queue(
        proposalId,
        timelock.address, 
        0, 
        "", 
        "0x", 
        "GENERAL"
    );

    // --- 4. Execute ---
    // Wait for Timelock Delay (TIME based)
    await time.increase(1209600 + 100); 

    // MANUAL CHECK
    const executeTx = await governor.connect(user1).execute(
        proposalId, 
        timelock.address, 
        0, 
        "", 
        "0x", 
        "GENERAL"
    );
    const executeReceipt = await executeTx.wait();

    // Check if the "ProposalExecuted" event exists in the logs
    // @ts-ignore
    const executeEvent = executeReceipt.events.find((e: any) => e.event === 'ProposalExecuted');
    expect(executeEvent).to.not.be.undefined;
  });
});