// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title TreasuryTimelock
 * @notice Holds funds, enforces time delays, and manages fund allocations.
 */
contract TreasuryTimelock {

    // --- Events ---
    event TransactionQueued(bytes32 indexed txHash, uint256 indexed eta);
    event TransactionExecuted(bytes32 indexed txHash, bytes result);
    event TransactionCanceled(bytes32 indexed txHash);
    event FundDeposited(string fundType, uint256 amount);
    event FundReleased(string fundType, address recipient, uint256 amount);

    // --- State Variables ---
    address public admin; // This will be the Governor contract
    uint256 public constant GRACE_PERIOD = 14 days; // Time after ETA where tx is still valid
    
    // Mapping of Transaction Hash -> Execution Time (ETA)
    mapping(bytes32 => uint256) public queuedTransactions;

    // Req 15: Track different fund allocations (Virtual Buckets)
    mapping(string => uint256) public fundBalances;

    // Access Control Modifier
    modifier onlyAdmin() {
        require(msg.sender == admin, "Timelock: Call must come from admin.");
        _;
    }

    constructor(address _admin) {
        admin = _admin;
    }

    // --- CRITICAL: Function to hand over power to Governor ---
    function setPendingAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }

    // --- Funding Logic ---

    // Deposit ETH into a specific bucket
    function deposit(string calldata fundType) external payable {
        fundBalances[fundType] += msg.value;
        emit FundDeposited(fundType, msg.value);
    }

    // Default receive function - assigns to "GENERAL"
    receive() external payable {
        fundBalances["GENERAL"] += msg.value;
        emit FundDeposited("GENERAL", msg.value);
    }

    // --- Timelock Core Logic ---

    function queueTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta,
        string memory fundType
    ) external onlyAdmin returns (bytes32) {
        require(eta >= block.timestamp, "Timelock: ETA must be in future");
        require(fundBalances[fundType] >= value, "Timelock: Insufficient funds in allocation");

        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta, fundType));
        queuedTransactions[txHash] = eta;

        emit TransactionQueued(txHash, eta);
        return txHash;
    }

    function executeTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta,
        string memory fundType
    ) external payable onlyAdmin returns (bytes memory) {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta, fundType));
        
        require(queuedTransactions[txHash] != 0, "Timelock: Transaction not queued.");
        require(block.timestamp >= eta, "Timelock: Transaction hasn't surpassed time lock.");
        require(block.timestamp <= eta + GRACE_PERIOD, "Timelock: Transaction is stale.");
        require(fundBalances[fundType] >= value, "Timelock: Insufficient funds.");

        queuedTransactions[txHash] = 0;
        fundBalances[fundType] -= value;

        bytes memory callData;
        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        require(success, "Timelock: Transaction execution reverted.");

        emit FundReleased(fundType, target, value);
        emit TransactionExecuted(txHash, returnData);

        return returnData;
    }

    function GRACE_PERIOD_VAL() external pure returns (uint256) {
        return GRACE_PERIOD;
    }
}