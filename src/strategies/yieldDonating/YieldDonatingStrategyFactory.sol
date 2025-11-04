// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {YieldDonatingStrategy, MarketParams} from "./YieldDonatingStrategy.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {YieldDonatingTokenizedStrategy} from "@octant-core/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

contract YieldDonatingStrategyFactory {
    event NewStrategy(address indexed strategy, address indexed asset);

    address public immutable emergencyAdmin;
    address public immutable tokenizedStrategyAddress;

    address public management;
    address public donationAddress;
    address public keeper;
    bool public enableBurning = true;

    /// @notice Track the deployments. asset => strategy
    mapping(address => address) public deployments;

    constructor(address _management, address _donationAddress, address _keeper, address _emergencyAdmin) {
        management = _management;
        donationAddress = _donationAddress;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;

        // Deploy the standard TokenizedStrategy implementation
        tokenizedStrategyAddress = address(new YieldDonatingTokenizedStrategy());
    }

    /**
     * @notice Deploy a new Auto-Repaying Spark-Morpho Multi-Strategy.
     * @param _asset The underlying asset for the strategy to use (DAI).
     * @param _name The name for the strategy.
     * @param _sparkPool Spark lending pool address
     * @param _sDAI Spark Savings DAI address
     * @param _morphoBlue Morpho Blue protocol address
     * @param _marketParams Morpho market parameters
     * @return The address of the new strategy.
     */
    function newStrategy(
        address _asset,
        string calldata _name,
        address _sparkPool,
        address _sDAI,
        address _morphoBlue,
        MarketParams calldata _marketParams
    ) external virtual returns (address) {
        // Deploy new Auto-Repaying Multi-Strategy
        IStrategyInterface _newStrategy = IStrategyInterface(
            address(
                new YieldDonatingStrategy(
                    _asset,
                    _name,
                    management,
                    keeper,
                    emergencyAdmin,
                    donationAddress,
                    enableBurning,
                    tokenizedStrategyAddress,
                    _sparkPool,
                    _sDAI,
                    _morphoBlue,
                    _marketParams
                )
            )
        );

        emit NewStrategy(address(_newStrategy), _asset);

        deployments[_asset] = address(_newStrategy);
        return address(_newStrategy);
    }

    function setAddresses(address _management, address _donationAddress, address _keeper) external {
        require(msg.sender == management, "!management");
        management = _management;
        donationAddress = _donationAddress;
        keeper = _keeper;
    }

    function setEnableBurning(bool _enableBurning) external {
        require(msg.sender == management, "!management");
        enableBurning = _enableBurning;
    }

    function isDeployedStrategy(address _strategy) external view returns (bool) {
        address _asset = IStrategyInterface(_strategy).asset();
        return deployments[_asset] == _strategy;
    }
}
