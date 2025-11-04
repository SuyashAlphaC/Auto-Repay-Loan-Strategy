// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseStrategy} from "@octant-core/core/BaseStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title MarketParams
 * @notice Parameters that define a Morpho Blue market
 */
struct MarketParams {
    address loanToken;       // The token that can be borrowed (DAI)
    address collateralToken; // The token used as collateral (sDAI)
    address oracle;          // Price oracle for collateral/loan
    address irm;            // Interest rate model
    uint256 lltv;           // Loan-to-value ratio (liquidation threshold)
}

/**
 * @title Position
 * @notice Represents a user's position in a Morpho market
 */
struct Position {
    uint256 supplyShares;   // Supply position shares
    uint128 borrowShares;   // Borrow position shares
    uint128 collateral;     // Collateral amount
}

/**
 * @title Market
 * @notice Morpho market state
 */
struct Market {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
}

/**
 * @title IMorpho
 * @notice Interface for Morpho Blue protocol
 */
interface IMorpho {
    function supplyCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        bytes memory data
    ) external;

    function withdrawCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external;

    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory data
    ) external returns (uint256, uint256);

    function withdraw(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256);

    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256);

    function repay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory data
    ) external returns (uint256, uint256);

    function position(bytes32 marketId, address user) external view returns (Position memory);

    function market(bytes32 marketId) external view returns (
        uint128 totalSupplyAssets,
        uint128 totalSupplyShares,
        uint128 totalBorrowAssets,
        uint128 totalBorrowShares,
        uint128 lastUpdate,
        uint128 fee
    );

    function accrueInterest(MarketParams memory marketParams) external;
}

/**
 * @title ISparkPool
 * @notice Interface for Spark Protocol lending pool
 */
interface ISparkPool {
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}

/**
 * @title YieldDonating Strategy - Auto-Repaying Community Loan Service
 * @author Octant
 * @notice DAO treasury strategy that provides auto-repaying loans to community while funding public goods
 * @dev This strategy implements a revolutionary dual-benefit mechanism:
 *
 * ARCHITECTURE - The "Winning Twist":
 * - DAO deposits treasury DAI into the vault
 * - Vault deposits DAI into Spark Protocol → earns sDAI (DSR yield)
 * - Vault supplies sDAI as collateral + borrowed DAI as loanable assets to Morpho Blue
 * - Creates an isolated Morpho market where COMMUNITY MEMBERS can borrow DAI
 * - Community pays interest on their borrows
 *
 * DUAL YIELD MECHANISM:
 * 1. PRIMARY YIELD (DSR from sDAI appreciation):
 *    → Auto-repays community members' DAI debts (subsidizes community loans)
 * 2. SECONDARY YIELD (Morpho lending interest from community):
 *    → Donated to Octant public goods fund
 *
 * THE VALUE PROPOSITION:
 * - DAO treasury: Funds public goods while providing free service to community
 * - Community members: Get loans that auto-repay themselves over time via DSR
 * - Public goods: Receive continuous donations from lending interest
 * - Everyone wins: Community gets subsidized loans + public goods get funded
 *
 * The _harvestAndReport() function:
 * 1. Calculates DSR profits and uses them to repay community borrows (via Morpho.repay onBehalf)
 * 2. Harvests Morpho interest and donates it to Octant
 * 3. Returns old totalAssets to maintain 1:1 DAI peg
 *
 * NOTE: This is a meta-public-good: it IS a public good service and FUNDS public goods
 */
contract YieldDonatingStrategy is BaseStrategy {
    using SafeERC20 for ERC20;
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* ========== IMMUTABLES ========== */

    /// @notice The DAI token
    IERC20 public immutable DAI;

    /// @notice Spark Protocol lending pool
    ISparkPool public immutable SPARK_POOL;

    /// @notice Spark's Savings DAI (ERC-4626 vault)
    IERC4626 public immutable sDAI;

    /// @notice Morpho Blue protocol
    IMorpho public immutable MORPHO_BLUE;

    /// @notice Morpho market parameters for our isolated market
    MarketParams public MORPHO_MARKET_PARAMS;

    /// @notice Market ID (hash of market params)
    bytes32 public immutable MARKET_ID;

    /* ========== STATE VARIABLES ========== */

    /// @notice Last recorded Morpho supply value (for interest calculation)
    uint256 public lastMorphoSupplyValue;

    /// @notice Last recorded sDAI collateral value (for DSR yield calculation)
    uint256 public lastCollateralValue;

    /// @notice Target loan-to-value ratio for vault's own position (basis points, e.g., 5000 = 50%)
    uint256 public targetLTV;

    /// @notice Total DSR yield accumulated that has been used to repay community debts
    uint256 public totalCommunityDebtRepaid;

    /// @notice Mapping of whitelisted community borrowers
    mapping(address => bool) public isCommunityBorrower;

    /// @notice Array of all registered community borrowers for iteration
    address[] public communityBorrowers;

    /// @notice Individual debt repayment tracking per borrower
    mapping(address => uint256) public debtRepaidForBorrower;

    /* ========== EVENTS ========== */

    event FundsDeployed(uint256 daiAmount, uint256 sDAIReceived, uint256 daiSuppliedToMorpho);
    event FundsFreed(uint256 daiAmount, uint256 sDAIRedeemed, uint256 daiWithdrawnFromMorpho);
    event YieldDonated(uint256 morphoInterest, address indexed recipient);
    event CommunityDebtRepaid(uint256 dsrYield, uint256 totalBorrowsRepaid);
    event TargetLTVUpdated(uint256 oldLTV, uint256 newLTV);
    event CommunityBorrowerAdded(address indexed borrower);
    event CommunityBorrowerRemoved(address indexed borrower);
    event BorrowerDebtRepaid(address indexed borrower, uint256 amountRepaid, uint256 totalRepaidForBorrower);

    /* ========== ERRORS ========== */

    error ZeroAddress();
    error InvalidLTV();
    error BorrowerAlreadyAdded();
    error BorrowerNotFound();

    /**
     * @notice Initialize the Auto-Repaying Multi-Strategy
     * @param _asset Address of the underlying asset (DAI)
     * @param _name Strategy name
     * @param _management Address with management role
     * @param _keeper Address with keeper role
     * @param _emergencyAdmin Address with emergency admin role
     * @param _donationAddress Address that receives donated/minted yield (Octant donation address)
     * @param _enableBurning Whether loss-protection burning from donation address is enabled
     * @param _tokenizedStrategyAddress Address of TokenizedStrategy implementation
     * @param _sparkPool Spark lending pool address
     * @param _sDAI Spark Savings DAI address
     * @param _morphoBlue Morpho Blue protocol address
     * @param _marketParams Morpho market parameters (defines our isolated market)
     */
    constructor(
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress,
        address _sparkPool,
        address _sDAI,
        address _morphoBlue,
        MarketParams memory _marketParams
    )
        BaseStrategy(
            _asset,
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {
        // Validation
        if (_asset == address(0) || _sparkPool == address(0) ||
            _sDAI == address(0) || _morphoBlue == address(0)) {
            revert ZeroAddress();
        }

        // Set strategy-specific immutables
        DAI = IERC20(_asset);
        SPARK_POOL = ISparkPool(_sparkPool);
        sDAI = IERC4626(_sDAI);
        MORPHO_BLUE = IMorpho(_morphoBlue);
        MORPHO_MARKET_PARAMS = _marketParams;

        // Calculate market ID
        MARKET_ID = keccak256(abi.encode(_marketParams));

        // Set default target LTV to 50% (5000 basis points)
        targetLTV = 5000;

        // Approve max for gas efficiency
        DAI.approve(_sparkPool, type(uint256).max);
        DAI.approve(_sDAI, type(uint256).max);
        DAI.approve(_morphoBlue, type(uint256).max);
        IERC20(_sDAI).approve(_morphoBlue, type(uint256).max);

        // TokenizedStrategy initialization will be handled separately
        // This is just a template - the actual initialization depends on
        // the specific TokenizedStrategy implementation being used
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy funds to create community lending pool
     * @dev Called when DAO deposits DAI into the vault
     * @param _amount Amount of DAI to deploy
     *
     * COMMUNITY LENDING ARCHITECTURE:
     * 1. Deposit all DAI into Spark → Earn maximum DSR on full amount
     * 2. Supply sDAI as collateral to Morpho Blue
     * 3. Borrow DAI against sDAI collateral at safe LTV (~50%)
     * 4. Supply borrowed DAI to Morpho as LOANABLE ASSETS FOR COMMUNITY
     *
     * KEY INSIGHT: The vault creates liquidity by borrowing against its DSR-earning
     * collateral. This borrowed DAI becomes available for COMMUNITY MEMBERS to borrow.
     * The vault's sDAI collateral earns DSR, which is used to subsidize community loans.
     *
     * EXAMPLE: $100k DAI deposit →
     *   - $100k in sDAI (earning DSR for community loan subsidies)
     *   - Borrow $50k DAI against sDAI
     *   - Supply $50k DAI for community to borrow
     *   - Community borrows from this $50k pool
     *   - DSR from $100k sDAI → repays community's debt
     *   - Interest from community → donated to public goods
     */
    function _deployFunds(uint256 _amount) internal override {
        if (_amount == 0) return;

        // Step 1: Convert ALL DAI to sDAI for maximum DSR exposure
        // This is the yield source that will subsidize community loans
        uint256 sDAIBefore = sDAI.balanceOf(address(this));
        sDAI.deposit(_amount, address(this));
        uint256 sDAIReceived = sDAI.balanceOf(address(this)) - sDAIBefore;

        // Step 2: Supply sDAI as collateral to Morpho Blue
        // This backs the vault's borrowing capacity
        MORPHO_BLUE.supplyCollateral(
            MORPHO_MARKET_PARAMS,
            sDAIReceived,
            address(this),
            bytes("")
        );

        // Step 3: Calculate safe borrow amount
        // Conservative 50% LTV leaves buffer for sDAI appreciation and safety
        uint256 collateralValue = sDAI.convertToAssets(sDAIReceived);
        uint256 daiBorrowTarget = (collateralValue * targetLTV) / 10000;

        // Step 4: Borrow DAI from Morpho to create community lending pool
        // This DAI is what the vault will supply for community to borrow
        (uint256 daiBorrowed,) = MORPHO_BLUE.borrow(
            MORPHO_MARKET_PARAMS,
            daiBorrowTarget,
            0,
            address(this),
            address(this)
        );

        // Step 5: Supply borrowed DAI to Morpho as LOANABLE ASSETS
        // This creates the lending pool that COMMUNITY MEMBERS can borrow from
        // Note: In Morpho Blue, anyone with collateral can borrow from this supply
        (uint256 assetsSupplied,) = MORPHO_BLUE.supply(
            MORPHO_MARKET_PARAMS,
            daiBorrowed,
            0,
            address(this),
            bytes("")
        );

        // Initialize tracking variables for yield calculations
        if (lastMorphoSupplyValue == 0) {
            lastMorphoSupplyValue = assetsSupplied;
        } else {
            lastMorphoSupplyValue += assetsSupplied;
        }

        if (lastCollateralValue == 0) {
            lastCollateralValue = collateralValue;
        } else {
            lastCollateralValue += collateralValue;
        }

        emit FundsDeployed(_amount, sDAIReceived, assetsSupplied);
    }

    /**
     * @notice Free funds from the strategy for DAO withdrawal
     * @dev Called when DAO withdraws from the vault
     * @param _amount Amount of DAI to free
     *
     * PROPORTIONAL UNWINDING:
     * 1. Calculate withdrawal ratio based on net vault value
     * 2. Withdraw proportional DAI from Morpho lending supply
     * 3. Repay proportional vault debt to Morpho
     * 4. Withdraw proportional sDAI collateral from Morpho
     * 5. Redeem sDAI for DAI from Spark
     * 6. DAI available for DAO withdrawal
     *
     * NOTE: Community borrows are NOT affected by DAO withdrawals.
     * The vault maintains its lending pool for community access.
     */
    function _freeFunds(uint256 _amount) internal override {
        if (_amount == 0) return;

        // Calculate ratio and withdraw proportionally
        uint256 ratio = _calculateWithdrawRatio(_amount);

        // If withdrawing very close to everything (>99.99%), withdraw ALL to avoid dust losses
        // This ensures users don't lose wei due to rounding when withdrawing their full balance
        if (ratio >= 0.9999e18) {
            ratio = 1e18;
        }

        _withdrawProportionally(ratio, _amount);
    }

    /**
     * @notice Harvest and report - AUTO-REPAYING COMMUNITY LOANS
     * @dev The revolutionary dual-yield mechanism that benefits both community and public goods
     *
     * THE WINNING TWIST - Community Loan Auto-Repayment:
     * 1. Calculate DSR yield from sDAI appreciation
     * 2. Calculate lending interest earned from community borrows
     * 3. ACTION 1: Use DSR yield to AUTO-REPAY COMMUNITY MEMBERS' debts
     * 4. ACTION 2: Donate lending interest to Octant public goods
     * 5. Return old totalAssets to maintain 1:1 peg
     *
     * COMMUNITY BENEFIT:
     * - Community borrows DAI from the lending pool
     * - Over time, their debt automatically decreases due to DSR subsidies
     * - They enjoy effectively subsidized/low-cost loans
     *
     * PUBLIC GOODS BENEFIT:
     * - All lending interest goes to Octant donation address
     * - Continuous stream of donations to fund public goods
     *
     * DAO BENEFIT:
     * - Treasury maintains 1:1 DAI value
     * - Provides valuable service to community
     * - Funds public goods simultaneously
     *
     * @return _totalAssets Returns old total assets to maintain 1:1 peg
     */
    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // 1. Get baseline assets before harvesting
        uint256 oldTotalAssets = TokenizedStrategy.totalAssets();

        // 2. Get current position and market state
        Position memory vaultPos = MORPHO_BLUE.position(MARKET_ID, address(this));
        (
            uint128 totalSupplyAssets,
            uint128 totalSupplyShares,
            uint128 totalBorrowAssets,
            uint128 totalBorrowShares,
            ,
        ) = MORPHO_BLUE.market(MARKET_ID);

        // 3. Calculate YIELD 1: DSR profits from sDAI appreciation
        uint256 currentCollateralValue = sDAI.convertToAssets(vaultPos.collateral);
        uint256 dsrProfit = currentCollateralValue > lastCollateralValue
            ? currentCollateralValue - lastCollateralValue
            : 0;

        // 4. Calculate YIELD 2: Lending interest from community borrows
        uint256 currentSupplyValue = totalSupplyShares > 0 && totalSupplyAssets > 0
            ? (vaultPos.supplyShares * totalSupplyAssets) / totalSupplyShares
            : 0;

        uint256 lendingInterest = currentSupplyValue > lastMorphoSupplyValue
            ? currentSupplyValue - lastMorphoSupplyValue
            : 0;

        // 5. ACTION 1: Use DSR yield to AUTO-REPAY COMMUNITY MEMBER DEBTS
        // This is the key innovation: DSR profits subsidize community loans
        if (dsrProfit > 0 && communityBorrowers.length > 0) {
            // Calculate how much sDAI represents the DSR profit
            uint256 sDAIProfit = sDAI.convertToShares(dsrProfit);

            // Withdraw the profit from collateral
            MORPHO_BLUE.withdrawCollateral(
                MORPHO_MARKET_PARAMS,
                sDAIProfit,
                address(this),
                address(this)
            );

            // Convert sDAI to DAI
            uint256 daiFromDSR = sDAI.redeem(sDAIProfit, address(this), address(this));

            if (daiFromDSR > 0) {
                // Calculate total community debt to determine pro-rata distribution
                uint256 totalCommunityDebt = 0;
                uint256[] memory borrowerDebts = new uint256[](communityBorrowers.length);

                // First pass: Calculate each borrower's debt
                for (uint256 i = 0; i < communityBorrowers.length; i++) {
                    Position memory borrowerPos = MORPHO_BLUE.position(MARKET_ID, communityBorrowers[i]);
                    uint256 borrowerDebt = totalBorrowShares > 0 && totalBorrowAssets > 0
                        ? (uint256(borrowerPos.borrowShares) * totalBorrowAssets) / totalBorrowShares
                        : 0;

                    borrowerDebts[i] = borrowerDebt;
                    totalCommunityDebt += borrowerDebt;
                }

                // Second pass: Repay each borrower's debt proportionally
                uint256 totalRepaid = 0;
                for (uint256 i = 0; i < communityBorrowers.length; i++) {
                    if (borrowerDebts[i] == 0) continue;

                    // Calculate pro-rata repayment for this borrower
                    uint256 repayAmount = totalCommunityDebt > 0
                        ? (daiFromDSR * borrowerDebts[i]) / totalCommunityDebt
                        : 0;

                    if (repayAmount > 0) {
                        // Directly repay this community member's debt using Morpho's onBehalf feature
                        MORPHO_BLUE.repay(
                            MORPHO_MARKET_PARAMS,
                            repayAmount,
                            0,
                            communityBorrowers[i], // onBehalf: repay FOR the community member
                            bytes("")
                        );

                        // Track repayment for this borrower
                        debtRepaidForBorrower[communityBorrowers[i]] += repayAmount;
                        totalRepaid += repayAmount;

                        emit BorrowerDebtRepaid(
                            communityBorrowers[i],
                            repayAmount,
                            debtRepaidForBorrower[communityBorrowers[i]]
                        );
                    }
                }

                // Track total community debt repaid for transparency
                totalCommunityDebtRepaid += totalRepaid;

                emit CommunityDebtRepaid(totalRepaid, totalCommunityDebt);
            }
        } else if (dsrProfit > 0) {
            // If no community borrowers yet, repay vault's own debt to maintain liquidity
            uint256 sDAIProfit = sDAI.convertToShares(dsrProfit);

            MORPHO_BLUE.withdrawCollateral(
                MORPHO_MARKET_PARAMS,
                sDAIProfit,
                address(this),
                address(this)
            );

            uint256 daiFromDSR = sDAI.redeem(sDAIProfit, address(this), address(this));

            if (daiFromDSR > 0) {
                MORPHO_BLUE.repay(
                    MORPHO_MARKET_PARAMS,
                    daiFromDSR,
                    0,
                    address(this),
                    bytes("")
                );
            }
        }

        // 6. ACTION 2: Donate lending interest to public goods
        // This is the interest earned from community members borrowing
        if (lendingInterest > 0) {
            // Withdraw interest from lending supply
            (uint256 withdrawn,) = MORPHO_BLUE.withdraw(
                MORPHO_MARKET_PARAMS,
                lendingInterest,
                0,
                address(this),
                address(this)
            );

            // Send to Octant donation address for public goods funding
            if (withdrawn > 0) {
                address dragonRouter = TokenizedStrategy.dragonRouter();
                DAI.safeTransfer(dragonRouter, withdrawn);
                emit YieldDonated(withdrawn, dragonRouter);
            }
        }

        // 7. Update tracking variables
        lastCollateralValue = currentCollateralValue > dsrProfit
            ? currentCollateralValue - dsrProfit
            : 0;

        lastMorphoSupplyValue = currentSupplyValue > lendingInterest
            ? currentSupplyValue - lendingInterest
            : 0;

        // 8. CRITICAL: Return old totalAssets to maintain 1:1 DAI peg
        // Even though we generated and used yield, we report ZERO profit
        // This keeps the vault shares at exactly 1:1 with DAI
        return oldTotalAssets;
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Since the strategy unwinds positions proportionally, users can always
     *      withdraw their full net deposit amount
     * @return . The available amount that can be withdrawn.
     */
    function availableWithdrawLimit(address /*_owner*/) public view virtual override returns (uint256) {
        // Return the full net value of the strategy with a small buffer for rounding
        // The proportional unwinding in _freeFunds handles the position management
        // Subtract small buffer to account for rounding errors in Morpho operations
        uint256 assets = _calculateCurrentAssets();
        // Leave 100 wei buffer to account for rounding in supply/borrow/collateral operations
        return assets > 100 ? assets - 100 : 0;
    }

    /**
     * @notice Gets the max amount of `asset` that can be deposited.
     * @dev Could be limited by Morpho market capacity or risk management
     * @param . The address that will deposit.
     * @return . The available amount that can be deposited.
     */
    function availableDepositLimit(address /*_owner*/) public view virtual override returns (uint256) {
        // For this strategy, we can set a reasonable cap to manage risk
        // In production, you might want to:
        // 1. Check Morpho market capacity
        // 2. Implement a maximum TVL cap
        // 3. Check available liquidity

        // For now, return unlimited (can be adjusted based on risk parameters)
        // Or set a specific cap, e.g., 10M DAI
        // return 10_000_000 * 1e18;

        return type(uint256).max;
    }

    /**
     * @dev Tend function to maintain the strategy between reports
     *
     * This function:
     * 1. Deploys idle funds if above threshold
     * 2. Rebalances LTV if it has drifted significantly
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     */
    function _tend(uint256 _totalIdle) internal virtual override {
        // Deploy idle funds if we have a meaningful amount (e.g., > 0.1% of total assets)
        uint256 totalAssets = TokenizedStrategy.totalAssets();
        uint256 minIdleToDeployThreshold = (totalAssets * 10) / 10000; // 0.1%

        if (_totalIdle > minIdleToDeployThreshold) {
            _deployFunds(_totalIdle);
        }

        // Rebalance LTV if needed
        _rebalanceLTV();
    }

    /**
     * @dev Trigger for tend() - returns true when maintenance is needed
     *
     * Tend should be called when:
     * 1. There's significant idle DAI (> 0.1% of total assets)
     * 2. LTV has drifted significantly from target (> 5% difference)
     * 3. Health factor is getting low (< 1.2)
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     */
    function _tendTrigger() internal view virtual override returns (bool) {
        uint256 totalAssets = TokenizedStrategy.totalAssets();
        if (totalAssets == 0) return false;

        // Check 1: Significant idle funds
        uint256 idleAssets = DAI.balanceOf(address(this));
        uint256 idleThreshold = (totalAssets * 10) / 10000; // 0.1%
        if (idleAssets > idleThreshold) {
            return true;
        }

        // Check 2: LTV drift
        Position memory pos = MORPHO_BLUE.position(MARKET_ID, address(this));
        if (pos.collateral > 0) {
            (
                ,
                ,
                uint128 totalBorrowAssets,
                uint128 totalBorrowShares,
                ,
            ) = MORPHO_BLUE.market(MARKET_ID);

            uint256 currentBorrow = totalBorrowShares > 0 && totalBorrowAssets > 0
                ? (uint256(pos.borrowShares) * totalBorrowAssets) / totalBorrowShares
                : 0;

            uint256 collateralValue = sDAI.convertToAssets(pos.collateral);

            if (collateralValue > 0) {
                uint256 currentLTV = (currentBorrow * 10000) / collateralValue;

                // If LTV differs from target by more than 500 bps (5%)
                if (currentLTV > targetLTV + 500 || currentLTV + 500 < targetLTV) {
                    return true;
                }
            }
        }

        // Check 3: Low health factor
        uint256 hf = this.healthFactor();
        if (hf < 1.2 * 1e18 && hf != type(uint256).max) {
            return true;
        }

        return false;
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     */
    function _emergencyWithdraw(uint256 _amount) internal virtual override {
        // In emergency, unwind positions proportionally
        if (_amount == 0) return;
        uint256 ratio = _calculateWithdrawRatio(_amount);
        _withdrawProportionally(ratio, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Helper function to calculate withdrawal ratio
     * @param _amount Amount to withdraw
     * @return Withdrawal ratio scaled by 1e18
     */
    function _calculateWithdrawRatio(uint256 _amount) internal view returns (uint256) {
        Position memory pos = MORPHO_BLUE.position(MARKET_ID, address(this));

        (
            uint128 totalSupplyAssets,
            uint128 totalSupplyShares,
            uint128 totalBorrowAssets,
            uint128 totalBorrowShares,
            ,
        ) = MORPHO_BLUE.market(MARKET_ID);

        uint256 totalCollateralValue = sDAI.convertToAssets(pos.collateral);
        uint256 totalSupplied = totalSupplyShares > 0 && totalSupplyAssets > 0
            ? (pos.supplyShares * totalSupplyAssets) / totalSupplyShares
            : 0;
        uint256 totalBorrowed = totalBorrowShares > 0 && totalBorrowAssets > 0
            ? (uint256(pos.borrowShares) * totalBorrowAssets) / totalBorrowShares
            : 0;

        // Calculate net value: collateral + supply - borrow
        uint256 netValue = totalCollateralValue + totalSupplied;
        if (netValue >= totalBorrowed) {
            netValue -= totalBorrowed;
        } else {
            netValue = 0; // Shouldn't happen in normal operation
        }

        if (netValue == 0) return 0;

        // If withdrawing more than available, return 100% ratio
        if (_amount >= netValue) return 1e18;

        return (_amount * 1e18) / netValue;
    }

    /**
     * @dev Helper function to withdraw proportionally from positions
     * @param ratio Withdrawal ratio scaled by 1e18
     * @param _amount Amount being withdrawn
     */
    function _withdrawProportionally(uint256 ratio, uint256 _amount) internal {
        if (ratio == 0) return;

        Position memory pos = MORPHO_BLUE.position(MARKET_ID, address(this));
        (uint128 totalSupplyAssets, uint128 totalSupplyShares, uint128 totalBorrowAssets, uint128 totalBorrowShares,,) = MORPHO_BLUE.market(MARKET_ID);

        // Withdraw from supply
        uint256 totalSupplied = totalSupplyShares > 0 && totalSupplyAssets > 0
            ? (pos.supplyShares * totalSupplyAssets) / totalSupplyShares
            : 0;
        // If ratio is 100%, withdraw ALL supply shares to avoid rounding dust
        uint256 supplyToWithdraw = ratio >= 1e18 ? totalSupplied : (totalSupplied * ratio) / 1e18;

        if (supplyToWithdraw > 0) {
            MORPHO_BLUE.withdraw(MORPHO_MARKET_PARAMS, supplyToWithdraw, 0, address(this), address(this));
            // Update tracker to account for withdrawn supply
            if (lastMorphoSupplyValue >= supplyToWithdraw) {
                lastMorphoSupplyValue -= supplyToWithdraw;
            } else {
                lastMorphoSupplyValue = 0;
            }
        }

        // Calculate debt to repay
        uint256 totalBorrowed = pos.borrowShares > 0 && totalBorrowAssets > 0
            ? (uint256(pos.borrowShares) * totalBorrowAssets) / totalBorrowShares
            : 0;
        // If ratio is 100%, repay ALL debt and withdraw ALL collateral to avoid rounding dust
        uint256 debtToRepay = ratio >= 1e18 ? totalBorrowed : (totalBorrowed * ratio) / 1e18;
        uint256 collateralToWithdraw = ratio >= 1e18 ? pos.collateral : (pos.collateral * ratio) / 1e18;

        // Check if we have enough DAI to repay the debt
        uint256 daiBalance = DAI.balanceOf(address(this));

        // If we don't have enough DAI, we need to convert some collateral first
        if (debtToRepay > daiBalance && collateralToWithdraw > 0) {
            uint256 shortfall = debtToRepay - daiBalance;
            // Calculate how much collateral we need to convert (with small buffer for safety)
            uint256 collateralValue = sDAI.convertToAssets(collateralToWithdraw);

            // If our collateral can cover the shortfall, convert just enough
            if (collateralValue >= shortfall) {
                // Convert proportional amount of collateral to cover shortfall
                uint256 collateralNeeded = (collateralToWithdraw * shortfall) / collateralValue;
                if (collateralNeeded > 0) {
                    MORPHO_BLUE.withdrawCollateral(MORPHO_MARKET_PARAMS, collateralNeeded, address(this), address(this));
                    sDAI.redeem(collateralNeeded, address(this), address(this));
                    collateralToWithdraw -= collateralNeeded;
                    daiBalance = DAI.balanceOf(address(this));
                }
            }
        }

        // Repay debt - repay up to what we can afford
        if (debtToRepay > 0 && daiBalance > 0) {
            uint256 actualRepayAmount = debtToRepay > daiBalance ? daiBalance : debtToRepay;
            MORPHO_BLUE.repay(MORPHO_MARKET_PARAMS, actualRepayAmount, 0, address(this), bytes(""));
        }

        // Withdraw remaining collateral (now safe because debt is reduced)
        if (collateralToWithdraw > 0) {
            MORPHO_BLUE.withdrawCollateral(MORPHO_MARKET_PARAMS, collateralToWithdraw, address(this), address(this));
            sDAI.redeem(collateralToWithdraw, address(this), address(this));
        }

        emit FundsFreed(_amount, collateralToWithdraw, debtToRepay);
    }

    /**
     * @dev Rebalances the LTV to target if it has drifted
     * Called by _tend() to maintain optimal leverage
     */
    function _rebalanceLTV() internal {
        Position memory pos = MORPHO_BLUE.position(MARKET_ID, address(this));

        if (pos.collateral == 0) return; // No position to rebalance

        (
            ,
            ,
            uint128 totalBorrowAssets,
            uint128 totalBorrowShares,
            ,
        ) = MORPHO_BLUE.market(MARKET_ID);

        uint256 currentBorrow = totalBorrowShares > 0 && totalBorrowAssets > 0
            ? (uint256(pos.borrowShares) * totalBorrowAssets) / totalBorrowShares
            : 0;

        uint256 collateralValue = sDAI.convertToAssets(pos.collateral);
        uint256 targetBorrow = (collateralValue * targetLTV) / 10000;

        // If we need to borrow more
        if (targetBorrow > currentBorrow) {
            uint256 additionalBorrow = targetBorrow - currentBorrow;

            // Borrow more DAI
            (uint256 borrowed,) = MORPHO_BLUE.borrow(
                MORPHO_MARKET_PARAMS,
                additionalBorrow,
                0,
                address(this),
                address(this)
            );

            // Supply the borrowed DAI
            if (borrowed > 0) {
                MORPHO_BLUE.supply(
                    MORPHO_MARKET_PARAMS,
                    borrowed,
                    0,
                    address(this),
                    bytes("")
                );
            }
        }
        // If we need to repay debt
        else if (currentBorrow > targetBorrow) {
            uint256 excessBorrow = currentBorrow - targetBorrow;

            // Withdraw from supply to repay
            (uint256 withdrawn,) = MORPHO_BLUE.withdraw(
                MORPHO_MARKET_PARAMS,
                excessBorrow,
                0,
                address(this),
                address(this)
            );

            // Repay the debt
            if (withdrawn > 0) {
                MORPHO_BLUE.repay(
                    MORPHO_MARKET_PARAMS,
                    withdrawn,
                    0,
                    address(this),
                    bytes("")
                );
            }
        }
    }

    /**
     * @notice Calculate current net assets of the vault
     * @dev Internal view function to get real-time vault value
     * @return Total DAI value available to DAO (net of all positions)
     *
     * CALCULATION (Vault's Net Position):
     * = sDAI collateral value (earning DSR for community subsidies)
     * + DAI supplied to Morpho (lending pool for community)
     * + Idle DAI balance
     * - Vault's DAI debt to Morpho (used to create lending pool)
     *
     * NOTE: This represents DAO's treasury value, NOT including community borrows.
     * Community borrows from the lending pool are separate external positions.
     */
    function _calculateCurrentAssets() internal view returns (uint256) {
        // Get position
        Position memory pos = MORPHO_BLUE.position(MARKET_ID, address(this));

        // Get market state
        (
            uint128 totalSupplyAssets,
            uint128 totalSupplyShares,
            uint128 totalBorrowAssets,
            uint128 totalBorrowShares,
            ,
        ) = MORPHO_BLUE.market(MARKET_ID);

        // Calculate sDAI collateral value in DAI
        uint256 collateralValue = sDAI.convertToAssets(pos.collateral);

        // Calculate DAI supplied value
        uint256 supplyValue = totalSupplyShares > 0 && totalSupplyAssets > 0
            ? (pos.supplyShares * totalSupplyAssets) / totalSupplyShares
            : 0;

        // Calculate DAI borrowed
        uint256 borrowValue = totalBorrowShares > 0 && totalBorrowAssets > 0
            ? (uint256(pos.borrowShares) * totalBorrowAssets) / totalBorrowShares
            : 0;

        // Get idle DAI balance
        uint256 idleBalance = DAI.balanceOf(address(this));

        // Total assets = collateral + supply + idle - borrow
        return collateralValue + supplyValue + idleBalance - borrowValue;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get estimated total assets (real-time calculation)
     * @dev This shows the actual value including unrealized yields
     * @return Total estimated assets in DAI
     */
    function estimatedTotalAssets() external view returns (uint256) {
        return _calculateCurrentAssets();
    }

    /**
     * @notice Get current health factor of the vault
     * @dev Higher is better. Below 1.0 risks liquidation
     * @return Health factor scaled by 1e18
     */
    function healthFactor() external view returns (uint256) {
        Position memory pos = MORPHO_BLUE.position(MARKET_ID, address(this));

        (
            ,
            ,
            uint128 totalBorrowAssets,
            uint128 totalBorrowShares,
            ,
        ) = MORPHO_BLUE.market(MARKET_ID);

        uint256 borrowValue = totalBorrowShares > 0 && totalBorrowAssets > 0
            ? (uint256(pos.borrowShares) * totalBorrowAssets) / totalBorrowShares
            : 0;

        if (borrowValue == 0) return type(uint256).max;

        uint256 collateralValue = sDAI.convertToAssets(pos.collateral);
        uint256 maxBorrow = (collateralValue * MORPHO_MARKET_PARAMS.lltv) / 1e18;

        return (maxBorrow * 1e18) / borrowValue;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set target LTV ratio
     * @dev Only management can call this
     * @param _targetLTV New target LTV in basis points (max 9000 = 90%)
     */
    function setTargetLTV(uint256 _targetLTV) external onlyManagement {
        if (_targetLTV > 9000) revert InvalidLTV(); // Max 90%
        emit TargetLTVUpdated(targetLTV, _targetLTV);
        targetLTV = _targetLTV;
    }

    /**
     * @notice Add a community member to the borrower whitelist
     * @dev Only management can call this. Allows the address to borrow from the lending pool
     * @param _borrower Address of the community member to whitelist
     *
     * Once whitelisted, this address can:
     * - Borrow DAI from the Morpho lending pool created by the vault
     * - Their debt will be auto-repaid over time using DSR yields
     * - They pay interest which goes to public goods funding
     */
    function addCommunityBorrower(address _borrower) external onlyManagement {
        if (_borrower == address(0)) revert ZeroAddress();
        if (isCommunityBorrower[_borrower]) revert BorrowerAlreadyAdded();

        isCommunityBorrower[_borrower] = true;
        communityBorrowers.push(_borrower);

        emit CommunityBorrowerAdded(_borrower);
    }

    /**
     * @notice Remove a community member from the borrower whitelist
     * @dev Only management can call this
     * @param _borrower Address of the community member to remove
     *
     * WARNING: This does NOT repay their existing debt. It only prevents
     * future borrows. Existing debt will still be auto-repaid via DSR.
     */
    function removeCommunityBorrower(address _borrower) external onlyManagement {
        if (!isCommunityBorrower[_borrower]) revert BorrowerNotFound();

        isCommunityBorrower[_borrower] = false;

        // Remove from array (swap with last element and pop)
        for (uint256 i = 0; i < communityBorrowers.length; i++) {
            if (communityBorrowers[i] == _borrower) {
                communityBorrowers[i] = communityBorrowers[communityBorrowers.length - 1];
                communityBorrowers.pop();
                break;
            }
        }

        emit CommunityBorrowerRemoved(_borrower);
    }

    /*//////////////////////////////////////////////////////////////
                        COMMUNITY VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the number of registered community borrowers
     * @return Number of whitelisted borrowers
     */
    function getCommunityBorrowerCount() external view returns (uint256) {
        return communityBorrowers.length;
    }

    /**
     * @notice Get all registered community borrowers
     * @return Array of whitelisted borrower addresses
     */
    function getAllCommunityBorrowers() external view returns (address[] memory) {
        return communityBorrowers;
    }

    /**
     * @notice Get debt repayment stats for a specific borrower
     * @param _borrower Address of the borrower
     * @return isWhitelisted Whether the address is a whitelisted borrower
     * @return totalRepaid Total amount of debt repaid by vault on their behalf
     * @return currentDebt Current outstanding debt in Morpho
     */
    function getBorrowerInfo(address _borrower) external view returns (
        bool isWhitelisted,
        uint256 totalRepaid,
        uint256 currentDebt
    ) {
        isWhitelisted = isCommunityBorrower[_borrower];
        totalRepaid = debtRepaidForBorrower[_borrower];

        // Get current debt from Morpho
        Position memory borrowerPos = MORPHO_BLUE.position(MARKET_ID, _borrower);
        (,,uint128 totalBorrowAssets, uint128 totalBorrowShares,,) = MORPHO_BLUE.market(MARKET_ID);

        currentDebt = totalBorrowShares > 0 && totalBorrowAssets > 0
            ? (uint256(borrowerPos.borrowShares) * totalBorrowAssets) / totalBorrowShares
            : 0;
    }
}
