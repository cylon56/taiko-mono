// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.20;

/// @title TaikoErrors
/// @notice This abstract contract provides custom error declartions used in
/// the Taiko protocol. Each error corresponds to specific situations where
/// exceptions might be thrown.
abstract contract TaikoErrors {
    // NOTE: The following custom errors must match the definitions in
    // `L1/libs/*.sol`.
    error L1_ALREADY_CONTESTED();
    error L1_ALREADY_PROVED();
    error L1_ASSIGNMENT_EXPIRED();
    error L1_ASSIGNMENT_INVALID_SIG();
    error L1_ASSIGNMENT_INVALID_PARAMS();
    error L1_ASSIGNMENT_INSUFFICIENT_FEE();
    error L1_ASSIGNED_PROVER_NOT_ALLOWED();
    error L1_BLOB_FOR_DA_DISABLED();
    error L1_BLOCK_MISMATCH();
    error L1_INSUFFICIENT_TOKEN();
    error L1_INVALID_ADDRESS();
    error L1_INVALID_AMOUNT();
    error L1_INVALID_BLOCK_ID();
    error L1_INVALID_CONFIG();
    error L1_INVALID_ETH_DEPOSIT();
    error L1_INVALID_PARAM();
    error L1_INVALID_PROOF();
    error L1_INVALID_TIER();
    error L1_INVALID_TRANSITION();
    error L1_NOT_ASSIGNED_PROVER();
    error L1_NO_BLOB_FOUND();
    error L1_PROPOSER_NOT_EOA();
    error L1_TIER_NOT_FOUND();
    error L1_TOO_MANY_BLOCKS();
    error L1_TRANSITION_ID_ZERO();
    error L1_TRANSITION_NOT_FOUND();
    error L1_TXLIST_TOO_LARGE();
    error L1_UNAUTHORIZED();
    error L1_UNEXPECTED_TRANSITION_ID();
    error L1_UNEXPECTED_TRANSITION_TIER();
}
