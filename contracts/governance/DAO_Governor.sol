// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// IMPORT the interface file we just created
import "../interfaces/IDAO.sol";

/**
 * @title DAO_Governor
 * @notice Manages proposal lifecycle, voting, and execution.
 */
contract DAO_Governor {

    // --- Enums & Structs (Req 6, 30) ---
    enum ProposalState { Pending, Active, Defeated, Succeeded, Queued, Executed, Expired }

    struct ProposalCore {
        address proposer;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool executed;
        uint256 eta; // For timelock
        uint8 proposalType; // 0: General, 1: Investment, 2: Operational
    }

    struct ProposalSettings {
        uint256 quorumPct;     // e.g. 4%
        uint256 voteDuration;  // In blocks
        uint256 timelockDelay; // In seconds
    }

    // --- State Variables ---
    IGovernanceStaking public stakingContract;
    ITreasuryTimelock public timelockContract;

    uint256 public proposalCount;
    mapping(uint256 => ProposalCore) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted; // Req 12: One vote per member
    mapping(uint8 => ProposalSettings) public typeSettings; // Req 3: Different settings per type

    uint256 public constant MIN_PROPOSAL_THRESHOLD = 1; // Min stake to propose (Req 26)

    // --- Events (Req 18, 29) ---
    event ProposalCreated(uint256 indexed proposalId, address proposer, string description);
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight);
    event ProposalQueued(uint256 id, uint256 eta);
    event ProposalExecuted(uint256 id);

    constructor(address _staking, address _timelock) {
        stakingContract = IGovernanceStaking(_staking);
        timelockContract = ITreasuryTimelock(_timelock);

        // Configure Types (Req 3, 16)
        // Type 0 (General): 4% Quorum, 3 day vote, 2 day delay
        typeSettings[0] = ProposalSettings(4, 21600, 2 days); 
        // Type 1 (High Conviction/Invest): 10% Quorum, 5 day vote, 5 day delay
        typeSettings[1] = ProposalSettings(10, 36000, 5 days);
        // Type 2 (Operational): 2% Quorum, 1 day vote, 1 day delay (Faster)
        typeSettings[2] = ProposalSettings(2, 7200, 1 days);
    }

    // --- Core Logic ---

    /**
     * @notice Creates a new proposal.
     * @dev Checks if the proposer has enough stake (Req 26).
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description,
        uint8 pType
    ) external returns (uint256) {
        // Req 26: Spam protection
        require(stakingContract.getPastVotes(msg.sender, block.number - 1) >= MIN_PROPOSAL_THRESHOLD, "Below proposal threshold");
        
        proposalCount++;
        uint256 pid = proposalCount;
        ProposalSettings memory settings = typeSettings[pType];

        proposals[pid] = ProposalCore({
            proposer: msg.sender,
            startBlock: block.number, // Snapshot block
            endBlock: block.number + settings.voteDuration,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            canceled: false,
            executed: false,
            eta: 0,
            proposalType: pType
        });
        
        emit ProposalCreated(pid, msg.sender, description);
        return pid;
    }

    /**
     * @notice Casts a vote on a proposal.
     * @param support 0=Against, 1=For, 2=Abstain
     */
    function castVote(uint256 proposalId, uint8 support) external {
        require(state(proposalId) == ProposalState.Active, "Voting is closed");
        require(!hasVoted[proposalId][msg.sender], "Already voted"); // Req 12

        uint256 weight = stakingContract.getPastVotes(msg.sender, proposals[proposalId].startBlock);
        require(weight > 0, "No voting power");

        if (support == 0) {
            proposals[proposalId].againstVotes += weight;
        } else if (support == 1) {
            proposals[proposalId].forVotes += weight;
        } else if (support == 2) {
            proposals[proposalId].abstainVotes += weight;
        }

        hasVoted[proposalId][msg.sender] = true;
        emit VoteCast(msg.sender, proposalId, support, weight);
    }

    /**
     * @notice Queues a successful proposal into the Timelock.
     */
    function queue(uint256 proposalId, address target, uint256 value, string memory signature, bytes memory data, string memory fundType) external {
        require(state(proposalId) == ProposalState.Succeeded, "Proposal not succeeded");
        
        ProposalCore storage p = proposals[proposalId];
        ProposalSettings memory settings = typeSettings[p.proposalType];
        
        uint256 eta = block.timestamp + settings.timelockDelay;
        p.eta = eta;

        timelockContract.queueTransaction(target, value, signature, data, eta, fundType);
        
        emit ProposalQueued(proposalId, eta);
    }

    /**
     * @notice Executes a queued proposal after the delay.
     */
    function execute(uint256 proposalId, address target, uint256 value, string memory signature, bytes memory data, string memory fundType) external {
        require(state(proposalId) == ProposalState.Queued, "Proposal not queued");
        ProposalCore storage p = proposals[proposalId];
        
        require(block.timestamp >= p.eta, "Timelock not finished");

        p.executed = true;
        
        timelockContract.executeTransaction(target, value, signature, data, p.eta, fundType);
        
        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Returns the current state of a proposal.
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        ProposalCore memory p = proposals[proposalId];

        if (p.canceled) return ProposalState.Defeated;
        if (p.executed) return ProposalState.Executed;

        if (block.number <= p.endBlock) {
            return ProposalState.Active;
        }
        
        if (p.forVotes > p.againstVotes && p.eta == 0) {
            return ProposalState.Succeeded;
        }
        
        if (p.eta != 0 && p.eta > 0) {
             return ProposalState.Queued;
        }

        return ProposalState.Defeated;
    }
}