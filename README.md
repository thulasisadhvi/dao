
# CryptoVentures DAO Governance System

A modular, on-chain governance system inspired by Compound and Aave. This DAO features **Quadratic Voting**, a **Time-Locked Treasury**, and a robust **Proposal Lifecycle**.

## 📊 System Architecture

```mermaid
graph TD
    User((User)) -->|1. Stakes ETH| Staking[GovernanceStaking.sol]
    User -->|2. Proposes| Governor[DAO_Governor.sol]
    
    subgraph Core System
        Staking -->|Calculates Voting Power (Sqrt)| Governor
        Governor -->|3. Queues Successful Proposal| Timelock[TreasuryTimelock.sol]
        Timelock -->|4. Holds Funds & Executes| Funds[(ETH Treasury)]
    end
    
    classDef contract fill:#f9f,stroke:#333,stroke-width:2px;
    class Staking,Governor,Timelock contract;

```

## 🚀 Setup & Installation (Evaluator Guide)

**Prerequisites:** Node.js v18+

1. **Clone the repository:**
```bash
git clone https://github.com/thulasisadhvi/dao.git
cd dao

```


2. **Install Dependencies:**
*(Note: A `.npmrc` file is included to handle peer dependency resolution automatically)*
```bash
npm install

```


3. **Environment Setup:**
```bash
cp .env.example .env

```


*Open `.env` and add your local parameters (or leave blank for local testing).*
4. **Start Local Blockchain:**
```bash
npx hardhat node

```



## 🛠 Deployment

**Run the Deployment & Seeding Script:**
*(In a new terminal window)*

```bash
npx hardhat run scripts/deploy.ts --network localhost

```

*Expected Output: Deploys all contracts, transfers Timelock admin rights to the Governor, and seeds the state with a test proposal.*

## ✅ Testing

To run the automated test suite verifying the full proposal lifecycle (Propose → Vote → Queue → Execute):

```bash
npx hardhat test

```

## 📜 Design Decisions

### 1. Quadratic Voting (Anti-Whale)

**Location:** `GovernanceStaking.sol`
Instead of 1 Token = 1 Vote, we implement **Quadratic Voting** (`Voting Power = √Stake`).

* **Why:** This prevents large holders ("whales") from dominating the DAO. A user with 100 ETH has only 10x the voting power of a user with 1 ETH, not 100x.

### 2. Time-Locked Treasury

**Location:** `TreasuryTimelock.sol`
Funds cannot be moved immediately after a vote passes.

* **Why:** Enforces a mandatory delay (e.g., 2 days) between passing a proposal and executing it. This gives users time to exit the protocol if they disagree with a malicious proposal.

### 3. Proposal Thresholds

**Location:** `DAO_Governor.sol`

* **Why:** Requires a minimum voting power to create a proposal, preventing spam and governance attacks.
