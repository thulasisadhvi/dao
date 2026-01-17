// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGovernanceStaking {
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);
    function stakeBalance(address account) external view returns (uint256);
}

interface ITreasuryTimelock {
    function queueTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta, string memory fundType) external returns (bytes32);
    function executeTransaction(address target, uint256 value, string memory signature, bytes memory data, uint256 eta, string memory fundType) external returns (bytes memory);
    function GRACE_PERIOD() external view returns (uint256);
}