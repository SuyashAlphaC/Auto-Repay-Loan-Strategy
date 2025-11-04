// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MarketParams, Position, IMorpho} from "../../strategies/yieldDonating/YieldDonatingStrategy.sol";

/**
 * @title MockMorphoBlue
 * @notice Mock Morpho Blue protocol for testing
 */
contract MockMorphoBlue is IMorpho {
    using SafeERC20 for IERC20;

    // Storage
    mapping(bytes32 => mapping(address => Position)) public positions;
    mapping(bytes32 => Market) public markets;
    mapping(bytes32 => bool) public marketExists;

    struct Market {
        uint128 totalSupplyAssets;
        uint128 totalSupplyShares;
        uint128 totalBorrowAssets;
        uint128 totalBorrowShares;
        uint128 lastUpdate;
        uint128 fee;
    }

    // Events
    event SupplyCollateral(bytes32 indexed marketId, address indexed user, uint256 assets);
    event WithdrawCollateral(bytes32 indexed marketId, address indexed user, uint256 assets);
    event Supply(bytes32 indexed marketId, address indexed user, uint256 assets, uint256 shares);
    event Withdraw(bytes32 indexed marketId, address indexed user, uint256 assets, uint256 shares);
    event Borrow(bytes32 indexed marketId, address indexed user, uint256 assets, uint256 shares);
    event Repay(bytes32 indexed marketId, address indexed user, uint256 assets, uint256 shares);

    function createMarket(MarketParams memory marketParams) external {
        bytes32 marketId = keccak256(abi.encode(marketParams));
        marketExists[marketId] = true;
    }

    function supplyCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        bytes memory
    ) external {
        bytes32 marketId = keccak256(abi.encode(marketParams));
        if (!marketExists[marketId]) marketExists[marketId] = true;

        IERC20(marketParams.collateralToken).safeTransferFrom(msg.sender, address(this), assets);
        positions[marketId][onBehalf].collateral += uint128(assets);

        emit SupplyCollateral(marketId, onBehalf, assets);
    }

    function withdrawCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external {
        bytes32 marketId = keccak256(abi.encode(marketParams));
        require(marketExists[marketId], "market not created");

        positions[marketId][onBehalf].collateral -= uint128(assets);
        IERC20(marketParams.collateralToken).safeTransfer(receiver, assets);

        emit WithdrawCollateral(marketId, onBehalf, assets);
    }

    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256,
        address onBehalf,
        bytes memory
    ) external returns (uint256, uint256) {
        bytes32 marketId = keccak256(abi.encode(marketParams));
        require(marketExists[marketId], "market not created");

        IERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), assets);

        Market storage mkt = markets[marketId];
        uint256 shares;
        if (mkt.totalSupplyShares == 0) {
            shares = assets;
        } else {
            shares = (assets * mkt.totalSupplyShares) / mkt.totalSupplyAssets;
        }

        positions[marketId][onBehalf].supplyShares += shares;
        mkt.totalSupplyAssets += uint128(assets);
        mkt.totalSupplyShares += uint128(shares);

        emit Supply(marketId, onBehalf, assets, shares);
        return (assets, shares);
    }

    function withdraw(
        MarketParams memory marketParams,
        uint256 assets,
        uint256,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256) {
        bytes32 marketId = keccak256(abi.encode(marketParams));
        require(marketExists[marketId], "market not created");

        Market storage mkt = markets[marketId];

        // Handle edge case: if no supply assets, no withdrawal
        if (mkt.totalSupplyAssets == 0 || assets == 0) {
            return (0, 0);
        }

        uint256 shares = (assets * mkt.totalSupplyShares) / mkt.totalSupplyAssets;

        // Don't withdraw more than available
        if (shares > positions[marketId][onBehalf].supplyShares) {
            shares = positions[marketId][onBehalf].supplyShares;
            assets = (shares * mkt.totalSupplyAssets) / mkt.totalSupplyShares;
        }

        positions[marketId][onBehalf].supplyShares -= shares;
        mkt.totalSupplyAssets -= uint128(assets);
        mkt.totalSupplyShares -= uint128(shares);

        IERC20(marketParams.loanToken).safeTransfer(receiver, assets);

        emit Withdraw(marketId, onBehalf, assets, shares);
        return (assets, shares);
    }

    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256) {
        bytes32 marketId = keccak256(abi.encode(marketParams));
        require(marketExists[marketId], "market not created");

        Market storage mkt = markets[marketId];
        uint256 shares;
        if (mkt.totalBorrowShares == 0) {
            shares = assets;
        } else {
            shares = (assets * mkt.totalBorrowShares) / mkt.totalBorrowAssets;
        }

        positions[marketId][onBehalf].borrowShares += uint128(shares);
        mkt.totalBorrowAssets += uint128(assets);
        mkt.totalBorrowShares += uint128(shares);

        IERC20(marketParams.loanToken).safeTransfer(receiver, assets);

        emit Borrow(marketId, onBehalf, assets, shares);
        return (assets, shares);
    }

    function repay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256,
        address onBehalf,
        bytes memory
    ) external returns (uint256, uint256) {
        bytes32 marketId = keccak256(abi.encode(marketParams));
        require(marketExists[marketId], "market not created");

        Market storage mkt = markets[marketId];

        // Handle edge case: if no borrow assets, no repayment
        if (mkt.totalBorrowAssets == 0 || assets == 0) {
            return (0, 0);
        }

        // Transfer only what's needed
        uint256 shares = (assets * mkt.totalBorrowShares) / mkt.totalBorrowAssets;

        // Don't repay more than borrowed
        if (shares > positions[marketId][onBehalf].borrowShares) {
            shares = positions[marketId][onBehalf].borrowShares;
            assets = (shares * mkt.totalBorrowAssets) / mkt.totalBorrowShares;
        }

        IERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), assets);

        positions[marketId][onBehalf].borrowShares -= uint128(shares);
        mkt.totalBorrowAssets -= uint128(assets);
        mkt.totalBorrowShares -= uint128(shares);

        emit Repay(marketId, onBehalf, assets, shares);
        return (assets, shares);
    }

    function position(bytes32 marketId, address user) external view returns (Position memory) {
        return positions[marketId][user];
    }

    function market(bytes32 marketId) external view returns (
        uint128 totalSupplyAssets,
        uint128 totalSupplyShares,
        uint128 totalBorrowAssets,
        uint128 totalBorrowShares,
        uint128 lastUpdate,
        uint128 fee
    ) {
        Market storage m = markets[marketId];
        return (
            m.totalSupplyAssets,
            m.totalSupplyShares,
            m.totalBorrowAssets,
            m.totalBorrowShares,
            m.lastUpdate,
            m.fee
        );
    }

    function accrueInterest(MarketParams memory marketParams) external {
        bytes32 marketId = keccak256(abi.encode(marketParams));
        require(marketExists[marketId], "market not created");

        Market storage mkt = markets[marketId];
        mkt.lastUpdate = uint128(block.timestamp);

        // Simulate 0.1% interest accrual
        if (mkt.totalBorrowAssets > 0) {
            uint256 interest = mkt.totalBorrowAssets / 1000; // 0.1%
            mkt.totalBorrowAssets += uint128(interest);
            mkt.totalSupplyAssets += uint128(interest);
        }
    }
}
