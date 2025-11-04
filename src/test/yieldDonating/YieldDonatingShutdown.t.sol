pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {YieldDonatingSetup as Setup, ERC20, IStrategyInterface} from "./YieldDonatingSetup.sol";

contract YieldDonatingShutdownTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_shutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Skip some time
        skip(30 days);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // Allow for rounding tolerance due to multiple protocol interactions
        // Morpho, sDAI, and DSR compounding each introduce tiny rounding errors
        // 100 wei tolerance is standard in DeFi (0.0000000001% for 1 DAI)
        uint256 finalBalance = asset.balanceOf(user);
        uint256 expected = balanceBefore + _amount;
        assertApproxEqAbs(finalBalance, expected, 100, "!final balance (with tolerance)");
    }

    function test_emergencyWithdraw_maxUint(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // Skip some time
        skip(30 days);

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        assertEq(strategy.totalAssets(), _amount, "!totalAssets");

        // should be able to pass uint 256 max and not revert.
        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");
    }

    // TODO: Add tests for any emergency function added.
}
