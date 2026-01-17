// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title GovernanceStaking
 * @notice Handles ETH deposits, delegation, and quadratic voting power calculation.
 * @dev Implements checkpoints to ensure voting power is fixed at the time of proposal creation.
 */
contract GovernanceStaking {
    
    // --- Events (Requirement 18) ---
    event Deposited(address indexed user, uint256 amount, uint256 newVotingPower);
    event Withdrawn(address indexed user, uint256 amount);
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

    // --- State Variables ---
    mapping(address => uint256) public stakeBalance; // Actual ETH staked
    mapping(address => address) public delegates;    // Who a user is delegating to
    
    // A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint224 votes;
    }

    // A record of each account's delegate voting power history
    mapping(address => Checkpoint[]) private _checkpoints;

    // --- Core Logic ---

    // Requirement 1: Members deposit ETH to receive influence
    function deposit() external payable {
        require(msg.value > 0, "Must deposit ETH");
        
        uint256 previousPower = _calculateVotingPower(stakeBalance[msg.sender]);
        stakeBalance[msg.sender] += msg.value;
        uint256 newPower = _calculateVotingPower(stakeBalance[msg.sender]);

        // Update the voting power of the delegate (or self if no delegate)
        _moveDelegates(delegates[msg.sender], delegates[msg.sender], int256(newPower) - int256(previousPower));
        
        emit Deposited(msg.sender, msg.value, newPower);
    }

    // Requirement 1 & 4: Quadratic Voting Logic to reduce whale dominance
    // Voting Power = Sqrt(ETH Stake)
    function _calculateVotingPower(uint256 ethAmount) internal pure returns (uint256) {
        if (ethAmount == 0) return 0;
        return sqrt(ethAmount);
    }

    // Helper: Square Root Function (Babylonian Method)
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    // Requirement 5: Delegation
    function delegate(address delegatee) external {
        address currentDelegate = delegates[msg.sender];
        uint256 delegatorPower = _calculateVotingPower(stakeBalance[msg.sender]);
        
        delegates[msg.sender] = delegatee;

        emit DelegateChanged(msg.sender, currentDelegate, delegatee);

        // Move the voting power from old delegate to new delegate
        _moveDelegates(currentDelegate, delegatee, int256(delegatorPower));
    }

    // Internal function to move votes between delegates
    function _moveDelegates(address srcRep, address dstRep, int256 amount) internal {
        if (srcRep != dstRep && amount != 0) {
            if (srcRep != address(0)) {
                uint32 srcRepNum = uint32(_checkpoints[srcRep].length);
                uint256 srcRepOld = srcRepNum > 0 ? _checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = uint256(int256(srcRepOld) - amount); // Subtraction safe because of logic
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint32 dstRepNum = uint32(_checkpoints[dstRep].length);
                uint256 dstRepOld = dstRepNum > 0 ? _checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = uint256(int256(dstRepOld) + amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    // Requirement 21: Historical voting records must be queryable
    function _writeCheckpoint(address delegatee, uint32 nCheckpoints, uint256 oldVotes, uint256 newVotes) internal {
        uint32 blockNumber = uint32(block.number);

        if (nCheckpoints > 0 && _checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            _checkpoints[delegatee][nCheckpoints - 1].votes = uint224(newVotes);
        } else {
            _checkpoints[delegatee].push(Checkpoint(blockNumber, uint224(newVotes)));
        }
        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    // Requirement 20: Read current voting power
    function getVotes(address account) external view returns (uint256) {
        uint32 nCheckpoints = uint32(_checkpoints[account].length);
        return nCheckpoints > 0 ? _checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    // Get past votes for a specific block (Crucial for Proposal Voting)
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256) {
        require(blockNumber < block.number, "Block not yet mined");
        uint32 nCheckpoints = uint32(_checkpoints[account].length);
        if (nCheckpoints == 0) return 0;

        // Binary search for the checkpoint
        if (_checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return _checkpoints[account][nCheckpoints - 1].votes;
        }
        if (_checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2;
            Checkpoint memory cp = _checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return _checkpoints[account][lower].votes;
    }
}