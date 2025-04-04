// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract DummyAggregator {
    uint8 public decimals = 8;
    int256 public latestAnswer = 100000000; // $1.00

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, latestAnswer, block.timestamp, block.timestamp, 1);
    }
}
