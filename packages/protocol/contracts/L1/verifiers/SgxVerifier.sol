// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.20;

import { ECDSAUpgradeable } from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";

import { EssentialContract } from "../../common/EssentialContract.sol";
import { Proxied } from "../../common/Proxied.sol";
import { LibBytesUtils } from "../../thirdparty/LibBytesUtils.sol";

import { TaikoData } from "../TaikoData.sol";

import { IVerifier } from "./IVerifier.sol";

/// @title SgxVerifier
/// @notice This contract is the implementation of verifying SGX signature
/// proofs on-chain. Please see references below!
/// Reference #1: https://ethresear.ch/t/2fa-zk-rollups-using-sgx/14462
/// Reference #2: https://github.com/gramineproject/gramine/discussions/1579
contract SgxVerifier is EssentialContract, IVerifier {
    /// @dev Each public-private key pair (Ethereum address) is generated within
    /// the SGX program when it boots up. The off-chain remote attestation
    /// ensures the validity of the program hash and has the capability of
    /// bootstrapping the network with trustworthy instances.
    struct Instance {
        address addr;
        uint64 addedAt; // We can calculate if expired
    }

    uint256 public constant INSTANCE_EXPIRY = 180 days;

    /// @dev For gas savings, we shall assign each SGX instance with an id
    /// so that when we need to set a new pub key, just write storage once.
    uint256 public nextInstanceId; // slot 1

    /// @dev One SGX instance is uniquely identified (on-chain) by it's ECDSA
    /// public key (or rather ethereum address). Once that address is used (by
    /// proof verification) it has to be overwritten by a new one (representing
    /// the same instance). This is due to side-channel protection. Also this
    /// public key shall expire after some time. (For now it is a long enough 6
    /// months setting.)
    mapping(uint256 instanceId => Instance) public instances; // slot 2

    uint256[48] private __gap;

    event InstanceAdded(
        uint256 indexed id,
        address indexed instance,
        address replaced,
        uint256 timstamp
    );

    error SGX_INVALID_INSTANCE();
    error SGX_INVALID_INSTANCES();
    error SGX_INVALID_PROOF();

    /// @notice Initializes the contract with the provided address manager.
    /// @param _addressManager The address of the address manager contract.
    function init(address _addressManager) external initializer {
        EssentialContract._init(_addressManager);
    }

    /// @notice Adds trusted SGX instances to the registry.
    /// @param _instances The address array of trusted SGX instances.
    function addInstances(address[] calldata _instances) external onlyOwner {
        if (_instances.length == 0) revert SGX_INVALID_INSTANCES();

        for (uint256 i; i < _instances.length; ++i) {
            _addInstance(_instances[i]);
        }
    }

    /// @notice Adds SGX instances to the registry by another SGX instance.
    /// @param id The id of the SGX instance who is adding new members.
    /// @param _instances The address array of SGX instances.
    /// @param signature The signature proving authenticity.
    function addInstances(
        uint256 id,
        address[] calldata _instances,
        bytes calldata signature
    )
        external
    {
        if (_instances.length == 0) revert SGX_INVALID_INSTANCES();

        bytes32 signedHash = keccak256(abi.encode("ADD_INSTANCES", _instances));
        address oldInstance = ECDSAUpgradeable.recover(signedHash, signature);
        if (!_isInstanceValid(id, oldInstance)) revert SGX_INVALID_INSTANCE();

        _replaceInstance(id, oldInstance, _instances[0]);
        for (uint256 i = 1; i < _instances.length; ++i) {
            _addInstance(_instances[i]);
        }
    }

    /// @inheritdoc IVerifier
    function verifyProof(
        Context calldata ctx,
        TaikoData.Transition calldata tran,
        TaikoData.TierProof calldata proof
    )
        external
    {
        // Do not run proof verification to contest an existing proof
        if (ctx.isContesting) return;

        // Size is: 87 bytes
        // 2 bytes + 20 bytes + 65 bytes (signature) = 87
        if (proof.data.length != 87) revert SGX_INVALID_PROOF();

        uint16 id = uint16(bytes2(LibBytesUtils.slice(proof.data, 0, 2)));
        address newInstance =
            address(bytes20(LibBytesUtils.slice(proof.data, 2, 20)));
        bytes memory signature = LibBytesUtils.slice(proof.data, 22);

        address oldInstance = ECDSAUpgradeable.recover(
            getSignedHash(tran, newInstance, ctx.prover, ctx.metaHash),
            signature
        );

        if (!_isInstanceValid(id, oldInstance)) revert SGX_INVALID_INSTANCE();
        _replaceInstance(id, oldInstance, newInstance);
    }

    function getSignedHash(
        TaikoData.Transition memory tran,
        address newInstance,
        address prover,
        bytes32 metaHash
    )
        public
        pure
        returns (bytes32 signedHash)
    {
        return keccak256(abi.encode(tran, newInstance, prover, metaHash));
    }

    function _addInstance(address instance) private {
        if (instance == address(0)) revert SGX_INVALID_INSTANCE();

        uint256 id = nextInstanceId++;
        instances[id] = Instance(instance, uint64(block.timestamp));
        emit InstanceAdded(id, instance, address(0), block.timestamp);
    }

    function _replaceInstance(
        uint256 id,
        address oldInstance,
        address newInstance
    )
        private
    {
        instances[id] = Instance(newInstance, uint64(block.timestamp));
        emit InstanceAdded(id, newInstance, oldInstance, block.timestamp);
    }

    function _isInstanceValid(
        uint256 id,
        address instance
    )
        private
        view
        returns (bool)
    {
        if (instance == address(0)) return false;
        if (instance != instances[id].addr) return false;
        return instances[id].addedAt + INSTANCE_EXPIRY > block.timestamp;
    }
}

/// @title ProxiedSgxVerifier
/// @notice Proxied version of the parent contract.
contract ProxiedSgxVerifier is Proxied, SgxVerifier { }
