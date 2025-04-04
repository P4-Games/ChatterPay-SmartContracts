// src/interfaces/AggregatorV3Interface.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Chainlink Price Feed Interface
 * @notice Interface for interacting with Chainlink price feed aggregators
 * @dev This interface allows reading price data from Chainlink's decentralized oracle network
 */
interface AggregatorV3Interface {
    /**
     * @notice Get the number of decimals for the price feed
     * @return The number of decimals used in price feed values
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Get a description of what the price feed is tracking
     * @return A string describing the price feed
     */
    function description() external view returns (string memory);

    /**
     * @notice Get the version number of the price feed aggregator
     * @return The version number
     */
    function version() external view returns (uint256);

    /**
     * @notice Get price data for a specific round
     * @param _roundId The round ID to get data for
     * @return roundId The round ID
     * @return answer The price value for this round
     * @return startedAt Timestamp when the round started
     * @return updatedAt Timestamp when the round was last updated
     * @return answeredInRound The round in which the answer was computed
     */
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /**
     * @notice Get the latest price data
     * @return roundId The round ID
     * @return answer The latest price value
     * @return startedAt Timestamp when the round started
     * @return updatedAt Timestamp when the round was last updated
     * @return answeredInRound The round in which the answer was computed
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
