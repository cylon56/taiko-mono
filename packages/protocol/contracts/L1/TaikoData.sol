// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.20;

/// @title TaikoData
/// @notice This library defines various data structures used in the Taiko
/// protocol.
library TaikoData {
    /// @dev Struct holding Taiko configuration parameters. See {TaikoConfig}.
    struct Config {
        // ---------------------------------------------------------------------
        // Group 1: General configs
        // ---------------------------------------------------------------------
        // The chain ID of the network where Taiko contracts are deployed.
        uint64 chainId;
        // ---------------------------------------------------------------------
        // Group 2: Block level configs
        // ---------------------------------------------------------------------
        // The maximum number of proposals allowed in a single block.
        uint64 blockMaxProposals;
        // Size of the block ring buffer, allowing extra space for proposals.
        uint64 blockRingBufferSize;
        // The maximum number of verifications allowed when a block is proposed.
        uint64 maxBlocksToVerifyPerProposal;
        // The maximum gas limit allowed for a block.
        uint32 blockMaxGasLimit;
        // The maximum allowed bytes for the proposed transaction list calldata.
        uint24 blockMaxTxListBytes;
        // ---------------------------------------------------------------------
        // Group 3: Proof related configs
        // ---------------------------------------------------------------------
        // The amount of Taiko token as a prover liveness bond
        uint96 livenessBond;
        // ---------------------------------------------------------------------
        // Group 4: ETH deposit related configs
        // ---------------------------------------------------------------------
        // The size of the ETH deposit ring buffer.
        uint256 ethDepositRingBufferSize;
        // The minimum number of ETH deposits allowed per block.
        uint64 ethDepositMinCountPerBlock;
        // The maximum number of ETH deposits allowed per block.
        uint64 ethDepositMaxCountPerBlock;
        // The minimum amount of ETH required for a deposit.
        uint96 ethDepositMinAmount;
        // The maximum amount of ETH allowed for a deposit.
        uint96 ethDepositMaxAmount;
        // The gas cost for processing an ETH deposit.
        uint256 ethDepositGas;
        // The maximum fee allowed for an ETH deposit.
        uint256 ethDepositMaxFee;
        // True if EIP-4844 is enabled for DA
        bool allowUsingBlobForDA;
    }

    /// @dev Struct holding state variables.
    struct StateVariables {
        uint64 genesisHeight;
        uint64 genesisTimestamp;
        uint64 nextEthDepositToProcess;
        uint64 numEthDeposits;
        uint64 numBlocks;
        uint64 lastVerifiedBlockId;
    }

    /// @dev Struct representing prover assignment
    struct TierFee {
        uint16 tier;
        uint128 fee;
    }

    struct TierProof {
        uint16 tier;
        bytes data;
    }

    struct ProverAssignment {
        address prover;
        address feeToken;
        TierFee[] tierFees;
        uint64 expiry;
        bytes signature;
    }

    struct BlockParams {
        ProverAssignment assignment;
        bytes32 extraData;
    }

    /// @dev Struct containing data only required for proving a block
    /// Note: On L2, `block.difficulty` is the pseudo name of
    /// `block.prevrandao`, which returns a random number provided by the layer
    /// 1 chain.
    struct BlockMetadata {
        bytes32 l1Hash; // slot 1
        bytes32 difficulty; // slot 2
        bytes32 blobHash; //or txListHash (if Blob not yet supported), // slot 3
        bytes32 extraData; // slot 4
        bytes32 depositsHash; // slot 5
        address coinbase; // L2 coinbase, // slot 6
        uint64 id;
        uint32 gasLimit;
        uint64 timestamp; // slot 7
        uint64 l1Height;
        uint16 minTier;
        bool blobUsed;
    }

    /// @dev Struct representing transition to be proven.
    struct Transition {
        bytes32 parentHash;
        bytes32 blockHash;
        bytes32 signalRoot;
        bytes32 graffiti;
    }

    /// @dev Struct representing state transition data.
    /// 10 slots reserved for upgradability, 6 slots used.
    struct TransitionState {
        bytes32 key; // slot 1, only written/read for the 1st state transition.
        bytes32 blockHash; // slot 2
        bytes32 signalRoot; // slot 3
        address prover; // slot 4
        uint96 validityBond;
        address contester; // slot 5
        uint96 contestBond;
        uint64 timestamp; // slot 6 (82 bits)
        uint16 tier;
        bytes32[4] __reserved;
    }

    /// @dev Struct containing data required for verifying a block.
    /// 10 slots reserved for upgradability, 3 slots used.
    struct Block {
        bytes32 metaHash; // slot 1
        address assignedProver; // slot 2
        uint96 livenessBond;
        uint64 blockId; // slot 3
        uint64 proposedAt;
        uint32 nextTransitionId;
        uint32 verifiedTransitionId;
        bytes32[7] __reserved;
    }

    /// @dev Struct representing an Ethereum deposit.
    /// 1 slot used.
    struct EthDeposit {
        address recipient;
        uint96 amount;
        uint64 id;
    }

    /// @dev Forge is only able to run coverage in case the contracts by default
    /// capable of compiling without any optimization (neither optimizer runs,
    /// no compiling --via-ir flag).
    /// In order to resolve stack too deep without optimizations, we needed to
    /// introduce outsourcing vars into structs below.
    struct SlotA {
        uint64 genesisHeight;
        uint64 genesisTimestamp;
        uint64 numEthDeposits;
        uint64 nextEthDepositToProcess;
    }

    struct SlotB {
        uint64 numBlocks;
        uint64 nextEthDepositToProcess;
        uint64 lastVerifiedBlockId;
    }

    /// @dev Struct holding the state variables for the {TaikoL1} contract.
    struct State {
        // Ring buffer for proposed blocks and a some recent verified blocks.
        mapping(uint64 blockId_mod_blockRingBufferSize => Block) blocks;
        // Indexing to transition ids (ring buffer not possible)
        mapping(
            uint64 blockId => mapping(bytes32 parentHash => uint32 transitionId)
            ) transitionIds;
        // Ring buffer for transitions
        mapping(
            uint64 blockId_mod_blockRingBufferSize
                => mapping(uint32 transitionId => TransitionState)
            ) transitions;
        // Ring buffer for Ether deposits
        mapping(uint256 depositId_mod_ethDepositRingBufferSize => uint256)
            ethDeposits;
        // In-protocol Taiko token balances
        mapping(address account => uint256 balance) tokenBalances;
        SlotA slotA; // slot 6
        SlotB slotB; // slot 7
        uint256[143] __gap;
    }
}
