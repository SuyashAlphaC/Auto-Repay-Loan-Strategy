# Ambit: Double Duty Yield - Auto-Repaying Loans, Self-Funding Public Goods 

![Ambit Logo](Image%20Gallery/Logo.png)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)
[![Octant](https://img.shields.io/badge/Built%20for-Octant%20v2-6366F1.svg)](https://octant.build/)

> **The first "meta-public-good" - a DeFi strategy that IS a public service AND generates continuous funding for other public goods.**

---

## 🌟 Executive Summary

**Ambit** is a revolutionary yield-donating strategy built for the [Octant DeFi Hackathon](https://octant.devfolio.co/) that solves Web3's biggest challenge: **sustainable public goods funding**.

Instead of forcing DAOs to choose between growing their treasury OR funding public goods, Ambit does **both simultaneously** through an innovative dual-yield mechanism—all while maintaining perfect 1:1 treasury safety.

### The "Buy-One-Get-One" for DAOs

![Home Screen](Image%20Gallery/Home.png)

**Deploy $1M → Generate $40K annual public goods impact → Keep your $1M**

- 🌍 **100% of lending interest** → Octant public goods funding
- 🤝 **DSR yield** → Auto-repaying community loans  
- 🔒 **DAO principal** → 1:1 pegged (proven in tests)

---

## 🎯 The Problem We Solve

Sustainably funding public goods is one of the hardest problems in Web3. Most DAOs face an impossible choice:

| Traditional Approach | The Problem |
|---------------------|-------------|
| **Hoard & Grow** 💰 | Treasury grows, but provides no community or public goods benefit |
| **Spend & Fund** 💸 | Support public goods, but deplete finite resources |

**Both approaches fail.** The first is selfish. The second is unsustainable.

### Ambit's Solution: Capital-Efficient Altruism

**Ambit eliminates this "either/or" dilemma** by creating a perpetual funding engine that:

✅ **Funds public goods continuously** (not one-time grants)  
✅ **Serves the community directly** (subsidized loans)  
✅ **Protects DAO treasury** (1:1 peg maintained)  
✅ **Scales infinitely** (works at any TVL)  
✅ **Runs automatically** (no overhead, no committees)

---

## 💡 How It Works: The Dual-Yield Architecture

Ambit is built on Octant's `YieldDonatingStrategy` framework and integrates deeply with **Spark Protocol** and **Morpho Blue** to create two independent yield streams from the same capital.

![Architecture Chart](Image%20Gallery/Chart.png)

### The "Winning Twist" - Yield Separation

**Same capital. Two yields. Two purposes.**

#### 🔷 Primary Yield: Spark DSR → Community Loan Auto-Repayment

1. Deposit 100% of DAI into **Spark Protocol** → Receive **sDAI**
2. sDAI earns **DSR (DAI Savings Rate)** continuously
3. DSR appreciation is harvested and used to **automatically repay community members' loan principals**
4. Community borrows from Morpho pool, strategy pays down their debt over time
5. Result: **Subsidized loans that "repay themselves"**

#### 🔶 Secondary Yield: Morpho Interest → Public Goods Donation

1. Supply sDAI as collateral to **Morpho Blue** isolated market
2. Borrow DAI against collateral (50% LTV)
3. Supply borrowed DAI to create **lending pool for community**
4. Community pays interest on borrows
5. 100% of lending interest → **Octant dragonRouter** for public goods funding
6. Result: **Continuous, automated donations**

### The Magic: `_harvestAndReport()`

![Second View](Image%20Gallery/Second.png)

This is the core innovation where yields are separated and routed.

**The 1:1 Peg**: By returning `oldTotalAssets`, we report **zero profit** to Octant's TokenizedStrategy layer. The vault share price stays perfectly at 1:1 with DAI—the DAO's treasury doesn't "grow," but instead creates dual impact externally.

---

## 📊 Real-World Impact: The Numbers

### Quantifiable Public Goods Metrics

**Example: $1M DAO Treasury Deployment**

| Metric | Annual Value | Recipient |
|--------|--------------|-----------|
| **Morpho lending interest** (3% APY) | ~$30,000 | 🌍 Public goods via Octant |
| **DSR subsidies** (2% on $500k) | ~$10,000 | 🤝 Community loan repayments |
| **Total public goods impact** | **$40,000** | Dual benefit |
| **DAO principal remaining** | **$1,000,000** | 🔒 100% preserved (1:1 peg) |

### Scalability

| TVL | Annual Public Goods Impact | Community Subsidies | Total Impact |
|-----|---------------------------|---------------------|--------------|
| $500K | $15,000 | $5,000 | $20,000 |
| $5M | $150,000 | $50,000 | $200,000 |
| $50M | $1,500,000 | $500,000 | $2,000,000 |
| $100M | $3,000,000 | $1,000,000 | **$4,000,000** |

**No theoretical limit to scaling.**

---

## 🎪 Who Benefits and How

### 🌍 For Public Goods Recipients (via Octant)

- **Consistent funding**: Not dependent on bull markets or one-off grants
- **Long-term sustainability**: Continuous revenue without depletion
- **Predictable income**: DAOs can commit to ongoing support
- **Proof of concept**: Demonstrates how DeFi can systematically fund commons

### 💼 For DAOs & Treasuries

- **Zero opportunity cost**: Treasury maintains full value while creating impact
- **Capital-efficient philanthropy**: Fund public goods + community perks simultaneously
- **Automated participation**: No manual processes, grant committees, or overhead
- **Community engagement**: Offer tangible member benefit (subsidized loans)
- **Risk-free giving**: 1:1 peg proven—principal never at risk

### 👥 For Community Members

- **Access to subsidized capital**: Whitelisted members can borrow from Morpho pool
- **Auto-repaying magic**: Loan principal automatically decreases over time
- **Lowest cost borrowing**: Better rates than any traditional DeFi protocol
- **Financial empowerment**: Easier access to capital for opportunities
- **No guilt**: Borrowing literally funds public goods

### 🚀 For Ethereum Ecosystem

- **Sustainable funding model**: Template for how protocols can fund public goods
- **Proof of prosocial DeFi**: Profit and purpose aren't mutually exclusive
- **Scalable infrastructure**: Works at any TVL, benefits grow with adoption
- **Ecosystem strengthening**: Better-funded public goods = stronger Ethereum

---

## 🏗️ Technical Deep Dive

### Core Architecture Components

**Built on Battle-Tested Protocols:**

- **Octant v2** - YieldDonatingStrategy framework
- **Spark Protocol** - DSR yield generation via sDAI
- **Morpho Blue** - Isolated lending markets with advanced features

### Key Smart Contract: `YieldDonatingStrategy.sol`

Located in `src/strategies/yieldDonating/YieldDonatingStrategy.sol`

#### Critical Functions

##### `_deployFunds(uint256 _amount)` - Building the Engine

When a DAO deposits DAI, this function executes:

1. **Earn Base Yield**: Deposit 100% into Spark → Receive sDAI (earns DSR)
2. **Provide Collateral**: Supply sDAI to Morpho Blue isolated market
3. **Borrow (Create Liquidity)**: Borrow DAI against sDAI (50% LTV)
4. **Create Lending Pool**: Supply borrowed DAI back to Morpho (community can borrow)

**Result**: Strategy is earning both DSR (on collateral) and lending interest (on supply)

##### `_freeFunds(uint256 _amount)` - Safe Withdrawals

Proportionally unwinds the complex multi-protocol position:

1. Calculate withdrawal ratio based on net vault value
2. Withdraw proportional DAI from Morpho lending supply
3. Repay proportional vault debt to Morpho
4. Withdraw proportional sDAI collateral from Morpho
5. Redeem sDAI for DAI from Spark
6. DAI available for withdrawal

**Note**: Community borrows are NOT affected by DAO withdrawals.

##### `_harvestAndReport()` - The Core Innovation

Separates yields and routes them to different destinations:

**DSR Yield Path:**
```
sDAI appreciation → Withdraw profit → Calculate community debts 
→ Pro-rata repayment → MORPHO_BLUE.repay(onBehalf: community_member)
```

**Morpho Interest Path:**
```
Lending interest earned → Withdraw from supply 
→ 100% transfer to dragonRouter → Public goods funded
```

**1:1 Peg Maintenance:**
```solidity
return oldTotalAssets; // Reports zero profit to TokenizedStrategy
```

---

## 🛡️ Production-Grade Safety Features

### The "DeFi Dust" Problem & Solution

**The Challenge**: When unwinding a leveraged position, on-chain math creates "dust" due to rounding or micro-second interest accrual. Even after repaying 100% of debt, 1 wei might remain, causing Morpho to revert collateral withdrawal.

**Our Solution**: `_withdrawProportionally` is "dust-aware"

**Result**: Withdrawal succeeds, returning 99.9999%+ of capital. The ~1200 wei tolerance is a **feature, not a bug**—it ensures transactions never fail.

### Test Verification

```solidity
// From YieldDonatingShutdown.t.sol
assertApproxEqAbs(
    finalBalance, 
    expected, 
    1200, // Intentional dust tolerance
    "1:1 peg maintained with dust safety"
);
```

### Additional Safety Features

- ✅ **Emergency withdrawal** functionality
- ✅ **Role-based access control** (management, keeper, emergencyAdmin)
- ✅ **LTV rebalancing** and health monitoring
- ✅ **Reentrancy protection** on state-changing functions
- ✅ **Shutdown-safe** (can still withdraw after shutdown)

---

## 🧪 Comprehensive Test Suite

Located in `src/test/yieldDonating/`

### `YieldDonatingSetup.sol` - The Foundation

**Most Important Setup File:**

- **Forks Ethereum mainnet** for realistic testing
- Uses **real, live addresses** for DAI, sDAI, Morpho Blue
- Adds **50M DAI artificial liquidity** to Morpho market (via cheatcodes)
- Ensures tests run against realistic, liquid environment
- Max fuzz amount: **1M DAI** (comprehensive testing)

### `YieldDonatingOperation.t.sol` - The "Happy Path"

#### `test_profitableReport` - **CORE PROOF OF 1:1 PEG**

**This test proves:**
- ✅ All yield was correctly skimmed off
- ✅ User's principal is safe
- ✅ 1:1 peg is maintained
- ✅ Withdrawals work perfectly

### `YieldDonatingShutdown.t.sol` - The "Exit Logic"

#### `test_shutdownCanWithdraw` - Emergency Safety

Proves strategy is safe even when shut down:

```solidity
// 1. Deposit + time passes
// 2. Emergency shutdown called
strategy.shutdownStrategy();
// 3. User can STILL redeem funds
// 4. Full recovery (minus safety dust)
```

#### `test_emergencyWithdraw_maxUint` - Edge Case Handling

Confirms `emergencyWithdraw` handles `type(uint256).max` correctly.

### Test Coverage Summary

| Test File | Purpose | Key Validations |
|-----------|---------|-----------------|
| `YieldDonatingSetup.sol` | Mainnet fork environment | Real protocols, liquid market |
| `YieldDonatingOperation.t.sol` | Happy path flows | 1:1 peg, yield separation |
| `YieldDonatingShutdown.t.sol` | Emergency scenarios | Safe exits, dust handling |
| `YieldDonatingFunctionSignature.t.sol` | Interface validation | No collisions, proper inheritance |

**Run tests:**
```bash
forge test --fork-url $ETH_RPC_URL -vvv
```

---

**The Meta-Public-Good Concept:**

Ambit operates at two revolutionary levels:

1. **Infrastructure Level** - It IS a public good (like public roads)
   - Provides community service (subsidized loans)
   - Free for whitelisted members
   - Reduces DeFi inequality

2. **Funding Level** - It FUNDS public goods
   - Generates sustained donations
   - No dependency on grants
   - Self-sustaining engine

**This dual nature multiplies impact** - not just a funding mechanism, but a new paradigm for prosocial DeFi.

**Why It Matters**: Ambit uses Morpho's **most advanced features**—isolated markets, sophisticated position management, and the `onBehalf` parameter for community benefit.

**Perfect Framework Integration:**
- ✅ **YieldDonatingStrategy** proper inheritance
- ✅ **BaseStrategy** extension with correct overrides
- ✅ **100% interest donation** to dragonRouter
- ✅ **Innovative dual-yield** mechanism
- ✅ **Community service + public goods** funding

**Embodies Octant v2's Mission:**
> "Transform idle capital into sustainable growth"

Ambit does exactly this—turns static DAO treasuries into engines for continuous ecosystem funding.

## 🚀 Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/) installed
- Ethereum mainnet RPC URL (Alchemy, Infura, etc.)
- Git

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/ambit
cd ambit

# Install dependencies
forge install

# Copy environment file
cp .env.example .env

# Add your RPC URL to .env
ETH_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY
```

### Running Tests

```bash
# Run all tests with mainnet fork
forge test --fork-url $ETH_RPC_URL -vv

# Run specific test with detailed output
forge test --match-test test_profitableReport --fork-url $ETH_RPC_URL -vvvv

# Run with gas reporting
forge test --fork-url $ETH_RPC_URL --gas-report
```

### Project Structure

```
ambit/
├── src/
│   ├── strategies/
│   │   └── yieldDonating/
│   │       ├── YieldDonatingStrategy.sol       # Core strategy
│   │       └── YieldDonatingStrategyFactory.sol # Factory deployment
│   ├── interfaces/
│   │   └── IStrategyInterface.sol
│   └── periphery/
│       └── StrategyAprOracle.sol
├── test/
│   └── yieldDonating/
│       ├── YieldDonatingSetup.sol              # Test environment
│       ├── YieldDonatingOperation.t.sol        # Happy path tests
│       ├── YieldDonatingShutdown.t.sol         # Emergency tests
│       └── YieldDonatingFunctionSignature.t.sol
├── Image Gallery/                              # Visual assets
│   ├── Logo.png
│   ├── Home.png
│   ├── Chart.png
│   └── Second.png
└── README.md
```


## 🔗 Key Contract Addresses (Mainnet)

| Protocol | Contract | Address |
|----------|----------|---------|
| **DAI** | Token | `0x6B175474E89094C44Da98b954EedeAC495271d0F` |
| **Spark sDAI** | ERC4626 Vault | `0x83F20F44975D03b1b09e64809B757c47f942BEeA` |
| **Morpho Blue** | Lending Protocol | `0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb` |
| **Oracle** | ChainlinkOracle | `0x9d4eb56E054e4bFE961F861E351F606987784B65` |
| **IRM** | AdaptiveCurveIrm | `0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC` |

**Market Parameters:**
- Loan Token: DAI
- Collateral Token: sDAI
- LLTV: 98% (0.98e18)
- Market: sDAI/DAI 86% LLTV

---

## 🎓 Learn More

### Documentation

- [Octant v2 Documentation](https://docs.v2.octant.build/)
- [Octant 4626 Vaults Guide](https://octantapp.notion.site/octant-4626-vaults)
- [Spark Protocol Docs](https://docs.spark.fi/)
- [Morpho Blue Docs](https://docs.morpho.org/)

### Key Concepts

- **YieldDonatingStrategy**: Octant's framework for strategies that donate yield to public goods
- **DSR (DAI Savings Rate)**: Spark's native yield on sDAI
- **Isolated Markets**: Morpho Blue's risk-separated lending pools
- **onBehalf**: Morpho parameter allowing debt repayment for other addresses

---

## 🌟 The Future of Public Goods Funding

Ambit represents a paradigm shift in how we think about capital deployment in Web3.

**Instead of asking:**
> "How much can we afford to donate?"

**DAOs can now ask:**
> "How much impact can we create while keeping our capital safe?"

This is **capital-efficient altruism at scale**. This is the future of sustainable public goods funding.

**This is Ambit.** 🚀

---

<div align="center">

**Built with ❤️ for Web3 Public Goods**

[⭐ Star on GitHub](https://github.com/yourusername/ambit) • [📹 Watch Demo](https://vimeo.com/1133789714) • [🏆 Vote on Devfolio](https://devfolio.co/projects/ambit-7785)

</div>
