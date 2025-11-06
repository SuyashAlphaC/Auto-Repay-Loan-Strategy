
// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {YieldDonatingStrategy as Strategy, ERC20, MarketParams, IMorpho} from "../../strategies/yieldDonating/YieldDonatingStrategy.sol";
import {YieldDonatingStrategyFactory as StrategyFactory} from "../../strategies/yieldDonating/YieldDonatingStrategyFactory.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {ITokenizedStrategy} from "@octant-core/core/interfaces/ITokenizedStrategy.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";
import {YieldDonatingTokenizedStrategy} from "@octant-core/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

/* ========== MOCK IMPORTS (Commented out for mainnet testing) ========== */
// import {MockERC20} from "../mocks/MockERC20.sol";
// import {MockERC4626} from "../mocks/MockERC4626.sol";
// import {MockMorphoBlue} from "../mocks/MockMorphoBlue.sol";

contract YieldDonatingSetup is Test, IEvents {
    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    StrategyFactory public strategyFactory;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public dragonRouter = address(3); // This is the donation address
    address public emergencyAdmin = address(5);

    // YieldDonating specific variables
    bool public enableBurning = true;
    address public tokenizedStrategyAddress;

    // Multi-strategy specific variables
    address public sparkPool;
    address public sDAI;
    address public morphoBlue;
    address public oracle;
    address public IRM;
    MarketParams public marketParams;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz amounts for DAI (18 decimals)
    // Min: 0.01 DAI, Max: set in setUp() based on market liquidity
    uint256 public maxFuzzAmount;
    uint256 public minFuzzAmount = 10_000_000_000_000_000; // 0.01 DAI

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    /* ========== MAINNET ADDRESSES ========== */
    address internal constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant SDAI_ADDRESS = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address internal constant MORPHO_BLUE_ADDRESS = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    // Morpho Blue Market: sDAI/DAI 86% LLTV  
    // Reference: https://app.morpho.org/market?id=0xb323495f7e4148be5643a4ea4a8221eef163e4bccfdedc2a6f4696baacbc86cc
    address internal constant ORACLE_ADDRESS = 0x9d4eb56E054e4bFE961F861E351F606987784B65; // ChainlinkOracle
    address internal constant IRM_ADDRESS = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC; // AdaptiveCurveIrm
    uint256 internal constant LLTV = 980000000000000000; // 98% (0.98e18)

    function setUp() public virtual {
        /* ========== REAL MAINNET IMPLEMENTATION ========== */
        // This requires forking Ethereum mainnet

        // Use real DAI token
        asset = ERC20(DAI_ADDRESS);

        // Use real Spark sDAI (acts as both Spark pool and sDAI token)
        sDAI = SDAI_ADDRESS;
        sparkPool = SDAI_ADDRESS; // sDAI is an ERC4626 vault, can deposit directly

        // Use real Morpho Blue
        morphoBlue = MORPHO_BLUE_ADDRESS;

        // Use real oracle and IRM from existing Morpho market
        oracle = ORACLE_ADDRESS;
        IRM = IRM_ADDRESS;

        // Setup real market parameters (sDAI/DAI market)
        marketParams = MarketParams({
            loanToken: DAI_ADDRESS,
            collateralToken: sDAI,
            oracle: oracle,
            irm: IRM,
            lltv: LLTV // 98% LLTV
        });

        // Set decimals
        decimals = asset.decimals();

        // ========== ADD ARTIFICIAL LIQUIDITY TO MORPHO MARKET ==========
        // The real mainnet market has limited liquidity (~27 DAI available)
        // Add artificial liquidity in the forked environment for comprehensive testing
        // Note: This only affects the local fork, not real mainnet
        address liquidityProvider = address(0x999999);
        uint256 liquidityAmount = 50_000_000 * 10 ** decimals; // 50M DAI

        // Airdrop DAI to liquidity provider (test cheatcode - only works in tests)
        deal(address(asset), liquidityProvider, liquidityAmount);

        // Supply DAI to Morpho market
        vm.startPrank(liquidityProvider);
        asset.approve(morphoBlue, liquidityAmount);

        // Supply to the market (0 shares means supply all assets)
        IMorpho(morphoBlue).supply(marketParams, liquidityAmount, 0, liquidityProvider, bytes(""));
        vm.stopPrank();

        // Set max fuzz amount - with artificial liquidity we can test larger amounts
        // Strategy borrows at 50% LTV, so 1M DAI deposit = ~500K DAI borrowed (well within liquidity)
        maxFuzzAmount = 1_000_000 * 10 ** decimals; // 1M DAI max for comprehensive testing

        // Deploy YieldDonatingTokenizedStrategy implementation
        tokenizedStrategyAddress = address(new YieldDonatingTokenizedStrategy());

        // Deploy strategy factory
        strategyFactory = new StrategyFactory(management, dragonRouter, keeper, emergencyAdmin);

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        // Label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(dragonRouter, "dragonRouter");
        vm.label(sDAI, "sDAI");
        vm.label(morphoBlue, "morphoBlue");
        vm.label(address(0x999999), "liquidityProvider");
    }

    /* ========== MOCK IMPLEMENTATION (Commented out) ========== */
    /*
    function setUp() public virtual {
        // Deploy mock DAI token
        MockERC20 mockDAI = new MockERC20("DAI Stablecoin", "DAI", 18);
        asset = ERC20(address(mockDAI));
        address testAssetAddress = address(mockDAI);

        // Mint some DAI to user for testing
        mockDAI.mint(user, 1_000_000 * 10 ** 18);

        // Deploy mock sDAI (ERC4626 vault)
        MockERC4626 mockSDAI = new MockERC4626(address(asset), "Savings DAI", "sDAI");
        sDAI = address(mockSDAI);
        sparkPool = address(mockSDAI); // sDAI acts as Spark pool for simplicity

        // Deploy mock Morpho Blue
        MockMorphoBlue mockMorphoBlue = new MockMorphoBlue();
        morphoBlue = address(mockMorphoBlue);

        // Setup mock addresses for oracle and IRM
        oracle = address(0x5000); // Mock oracle
        IRM = address(0x6000);    // Mock IRM

        // Setup market parameters
        marketParams = MarketParams({
            loanToken: testAssetAddress,
            collateralToken: sDAI,
            oracle: oracle,
            irm: IRM,
            lltv: 0.86e18 // 86% LLTV
        });

        // Create the market in MockMorphoBlue
        mockMorphoBlue.createMarket(marketParams);

        // Mint some DAI to the mock contracts for liquidity
        mockDAI.mint(address(mockMorphoBlue), 10_000_000 * 10 ** 18);

        // Set decimals
        decimals = asset.decimals();

        // Set max fuzz amount to 1,000,000 of the asset
        maxFuzzAmount = 1_000_000 * 10 ** decimals;

        // Deploy YieldDonatingTokenizedStrategy implementation
        tokenizedStrategyAddress = address(new YieldDonatingTokenizedStrategy());

        strategyFactory = new StrategyFactory(management, dragonRouter, keeper, emergencyAdmin);

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(dragonRouter, "dragonRouter");
    }
    */
    /* ========== END MOCK IMPLEMENTATION ========== */

    function setUpStrategy() public returns (address) {
        // Deploy the Auto-Repaying Community Loan Strategy
        IStrategyInterface _strategy = IStrategyInterface(
            address(
                new Strategy(
                    address(asset),
                    "Auto-Repaying Community Loan Strategy",
                    management,
                    keeper,
                    emergencyAdmin,
                    dragonRouter, // Use dragonRouter as the donation address
                    enableBurning,
                    tokenizedStrategyAddress,
                    sparkPool,
                    sDAI,
                    morphoBlue,
                    marketParams
                )
            )
        );

        return address(_strategy);
    }

    function depositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public view {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(address(_strategy));
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setDragonRouter(address _newDragonRouter) public {
        vm.prank(management);
        ITokenizedStrategy(address(strategy)).setDragonRouter(_newDragonRouter);

        // Fast forward to bypass cooldown
        skip(7 days);

        // Anyone can finalize after cooldown
        ITokenizedStrategy(address(strategy)).finalizeDragonRouterChange();
    }

    function setEnableBurning(bool _enableBurning) public {
        vm.prank(management);
        // Call using low-level call since setEnableBurning may not be in all interfaces
        (bool success, ) = address(strategy).call(abi.encodeWithSignature("setEnableBurning(bool)", _enableBurning));
        require(success, "setEnableBurning failed");
    }
}
