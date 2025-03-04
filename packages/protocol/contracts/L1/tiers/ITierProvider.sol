// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.20;

/// @title ITierProvider
/// @notice Defines interface to return tier configuration.
interface ITierProvider {
    struct Tier {
        bytes32 verifierName;
        uint96 validityBond;
        uint96 contestBond;
        uint24 cooldownWindow;
        uint16 provingWindow;
        uint8 maxBlocksToVerify;
    }

    /// @dev Retrieves the configuration for a specified tier.
    function getTier(uint16 tierId) external view returns (Tier memory);

    /// @dev Retrieves the IDs of all supported tiers.
    function getTierIds() external view returns (uint16[] memory);

    /// @dev Determines the minimal tier for a block based on a random input.
    function getMinTier(uint256 rand) external view returns (uint16);
}

/// @dev Tier ID cannot be zero!
library LibTiers {
    uint16 public constant TIER_OPTIMISTIC = 100;
    uint16 public constant TIER_SGX = 200;
    uint16 public constant TIER_PSE_ZKEVM = 300;
    uint16 public constant TIER_SGX_AND_PSE_ZKEVM = 400;
    uint16 public constant TIER_GUARDIAN = 1000;
}
