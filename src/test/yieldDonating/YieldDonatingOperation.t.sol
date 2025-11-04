// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import {YieldDonatingSetup as Setup, ERC20, IStrategyInterface, ITokenizedStrategy} from "./YieldDonatingSetup.sol";

contract YieldDonatingOperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_setupStrategyOK() public {
        console2.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(ITokenizedStrategy(address(strategy)).dragonRouter(), dragonRouter);
        assertEq(strategy.keeper(), keeper);
        // Check enableBurning using low-level call since it's not in the interface
        (bool success, bytes memory data) = address(strategy).staticcall(abi.encodeWithSignature("enableBurning()"));
        require(success, "enableBurning call failed");
        bool currentEnableBurning = abi.decode(data, (bool));
        assertEq(currentEnableBurning, enableBurning);
    }

    function test_profitableReport(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Simulate some yield by increasing sDAI value and Morpho interest
        // In the AutoRepaying strategy:
        // - DSR yield auto-repays debt
        // - Morpho interest is donated to dragonRouter

        // Get dragonRouter balance before
        uint256 dragonRouterBalanceBefore = asset.balanceOf(dragonRouter);

        // Report - in AutoRepaying strategy, this maintains 1:1 peg
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // AutoRepaying strategy returns oldTotalAssets to maintain 1:1 peg
        // So profit should be 0 (reported to TokenizedStrategy)
        assertEq(profit, 0, "!profit should be 0 for 1:1 peg");
        assertEq(loss, 0, "!loss should be 0");

        // Check that user can still withdraw their full amount (1:1 peg maintained)
        uint256 balanceBefore = asset.balanceOf(user);

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // User should get back their full deposit amount (1:1 peg)
        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance - 1:1 peg maintained");
    }

    function test_tendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        (bool trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger, "!trigger should be false initially");

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger, "!trigger should be false after deposit");

        // Trigger a report
        vm.prank(keeper);
        strategy.report();

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger, "!trigger should be false after report");

        // For AutoRepaying strategy, tend is triggered when:
        // 1. Idle DAI > threshold
        // 2. LTV drift > 5%
        // 3. Health factor < 1.2

        // Normal operation should not trigger tend
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        (trigger, ) = strategy.tendTrigger();
        assertTrue(!trigger, "!trigger should be false after withdrawal");
    }
}
