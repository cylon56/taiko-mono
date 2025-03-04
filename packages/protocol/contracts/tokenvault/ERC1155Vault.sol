// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.20;

import { Create2Upgradeable } from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/Create2Upgradeable.sol";
import {
    ERC1155ReceiverUpgradeable,
    IERC1155ReceiverUpgradeable
} from
    "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC1155/utils/ERC1155ReceiverUpgradeable.sol";
import {
    ERC1155Upgradeable,
    IERC1155Upgradeable
} from
    "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC1155/ERC1155Upgradeable.sol";

import { Proxied } from "../common/Proxied.sol";
import { IBridge, IRecallableSender } from "../bridge/IBridge.sol";
import { LibAddress } from "../libs/LibAddress.sol";
import { LibDeploy } from "../libs/LibDeploy.sol";

import { BaseVault, BaseNFTVault } from "./BaseNFTVault.sol";
import { ProxiedBridgedERC1155 } from "./BridgedERC1155.sol";

/// @title ERC1155NameAndSymbol
/// @notice Interface for ERC1155 contracts that provide name() and symbol()
/// functions. These functions may not be part of the official interface but are
/// used by
/// some contracts.
interface ERC1155NameAndSymbol {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}

/// @title ERC1155Vault
/// @dev Labeled in AddressResolver as "erc1155_vault"
/// @notice This vault holds all ERC1155 tokens that users have deposited.
/// It also manages the mapping between canonical tokens and their bridged
/// tokens.
contract ERC1155Vault is BaseNFTVault, ERC1155ReceiverUpgradeable {
    using LibAddress for address;

    uint256[50] private __gap;

    /// @notice Transfers ERC1155 tokens to this vault and sends a message to
    /// the destination chain so the user can receive the same (bridged) tokens
    /// by invoking the message call.
    /// @param op Option for sending the ERC1155 token.
    function sendToken(BridgeTransferOp calldata op)
        external
        payable
        nonReentrant
        whenNotPaused
        whenOperationValid(op)
        returns (IBridge.Message memory _message)
    {
        for (uint256 i; i < op.amounts.length; ++i) {
            if (op.amounts[i] == 0) revert VAULT_INVALID_AMOUNT();
        }
        // Check token interface support
        if (!op.token.supportsInterface(ERC1155_INTERFACE_ID)) {
            revert VAULT_INTERFACE_NOT_SUPPORTED();
        }

        // Store variables in memory to avoid stack-too-deep error
        uint256[] memory _amounts = op.amounts;
        address _token = op.token;
        uint256[] memory _tokenIds = op.tokenIds;

        // Create a message to send to the destination chain
        IBridge.Message memory message;
        message.destChainId = op.destChainId;
        message.data = _encodeDestinationCall(msg.sender, op);
        message.user = msg.sender;
        message.to = resolve(message.destChainId, name(), false);
        message.gasLimit = op.gasLimit;
        message.value = msg.value - op.fee;
        message.fee = op.fee;
        message.refundTo = op.refundTo;
        message.memo = op.memo;

        // Send the message and obtain the message hash
        bytes32 msgHash;
        (msgHash, _message) = IBridge(resolve("bridge", false)).sendMessage{
            value: msg.value
        }(message);

        // Emit TokenSent event
        emit TokenSent({
            msgHash: msgHash,
            from: _message.user,
            to: op.to,
            destChainId: _message.destChainId,
            token: _token,
            tokenIds: _tokenIds,
            amounts: _amounts
        });
    }

    /// @notice This function can only be called by the bridge contract while
    /// invoking a message call. See sendToken, which sets the data to invoke
    /// this function.
    /// @param ctoken The canonical ERC1155 token which may or may not live on
    /// this chain. If not, a BridgedERC1155 contract will be deployed.
    /// @param from The source address.
    /// @param to The destination address.
    /// @param tokenIds The tokenIds to be sent.
    /// @param amounts The amounts to be sent.
    function receiveToken(
        CanonicalNFT calldata ctoken,
        address from,
        address to,
        uint256[] memory tokenIds,
        uint256[] memory amounts
    )
        external
        payable
        nonReentrant
        whenNotPaused
    {
        // Check context validity
        IBridge.Context memory ctx = checkProcessMessageContext();

        address _to = to == address(0) || to == address(this) ? from : to;
        address token;

        unchecked {
            if (ctoken.chainId == block.chainid) {
                // Token lives on this chain
                token = ctoken.addr;
                for (uint256 i; i < tokenIds.length; ++i) {
                    ERC1155Upgradeable(token).safeTransferFrom({
                        from: address(this),
                        to: _to,
                        id: tokenIds[i],
                        amount: amounts[i],
                        data: ""
                    });
                }
            } else {
                // Token does not live on this chain
                token = _getOrDeployBridgedToken(ctoken);
                for (uint256 i; i < tokenIds.length; ++i) {
                    ProxiedBridgedERC1155(token).mint(
                        _to, tokenIds[i], amounts[i]
                    );
                }
            }
        }

        _to.sendEther(msg.value);

        emit TokenReceived({
            msgHash: ctx.msgHash,
            from: from,
            to: to,
            srcChainId: ctx.srcChainId,
            token: token,
            tokenIds: tokenIds,
            amounts: amounts
        });
    }

    /// @inheritdoc IRecallableSender
    function onMessageRecalled(
        IBridge.Message calldata message,
        bytes32 msgHash
    )
        external
        payable
        override
        nonReentrant
        whenNotPaused
    {
        checkRecallMessageContext();

        (
            CanonicalNFT memory nft,
            ,
            ,
            uint256[] memory tokenIds,
            uint256[] memory amounts
        ) = abi.decode(
            message.data[4:],
            (CanonicalNFT, address, address, uint256[], uint256[])
        );

        if (nft.addr == address(0)) revert VAULT_INVALID_TOKEN();

        unchecked {
            if (isBridgedToken[nft.addr]) {
                for (uint256 i; i < tokenIds.length; ++i) {
                    ProxiedBridgedERC1155(nft.addr).mint(
                        message.user, tokenIds[i], amounts[i]
                    );
                }
            } else {
                for (uint256 i; i < tokenIds.length; ++i) {
                    IERC1155Upgradeable(nft.addr).safeTransferFrom({
                        from: address(this),
                        to: message.user,
                        id: tokenIds[i],
                        amount: amounts[i],
                        data: ""
                    });
                }
            }
        }
        // Send back Ether
        message.user.sendEther(message.value);
        // Emit TokenReleased event
        emit TokenReleased({
            msgHash: msgHash,
            from: message.user,
            token: nft.addr,
            tokenIds: tokenIds,
            amounts: amounts
        });
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    )
        external
        pure
        returns (bytes4)
    {
        return IERC1155ReceiverUpgradeable.onERC1155BatchReceived.selector;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    )
        external
        pure
        returns (bytes4)
    {
        return IERC1155ReceiverUpgradeable.onERC1155Received.selector;
    }

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(BaseVault, ERC1155ReceiverUpgradeable)
        returns (bool)
    {
        return interfaceId == type(ERC1155ReceiverUpgradeable).interfaceId
            || BaseVault.supportsInterface(interfaceId);
    }

    function name() public pure override returns (bytes32) {
        return "erc1155_vault";
    }

    /// @dev Encodes sending bridged or canonical ERC1155 tokens to the user.
    /// @param user The user's address.
    /// @param op BridgeTransferOp data.
    /// @return msgData Encoded message data.
    function _encodeDestinationCall(
        address user,
        BridgeTransferOp memory op
    )
        private
        returns (bytes memory msgData)
    {
        CanonicalNFT memory nft;
        unchecked {
            // is a btoken, meaning, it does not live on this chain
            if (isBridgedToken[op.token]) {
                nft = bridgedToCanonical[op.token];
                for (uint256 i; i < op.tokenIds.length; ++i) {
                    ProxiedBridgedERC1155(op.token).burn(
                        user, op.tokenIds[i], op.amounts[i]
                    );
                }
            } else {
                // is a ctoken token, meaning, it lives on this chain
                nft = CanonicalNFT({
                    chainId: uint64(block.chainid),
                    addr: op.token,
                    symbol: "",
                    name: ""
                });
                ERC1155NameAndSymbol t = ERC1155NameAndSymbol(op.token);
                try t.name() returns (string memory _name) {
                    nft.name = _name;
                } catch { }
                try t.symbol() returns (string memory _symbol) {
                    nft.symbol = _symbol;
                } catch { }
                for (uint256 i; i < op.tokenIds.length; ++i) {
                    ERC1155Upgradeable(op.token).safeTransferFrom({
                        from: msg.sender,
                        to: address(this),
                        id: op.tokenIds[i],
                        amount: op.amounts[i],
                        data: ""
                    });
                }
            }
        }
        msgData = abi.encodeWithSelector(
            ERC1155Vault.receiveToken.selector,
            nft,
            user,
            op.to,
            op.tokenIds,
            op.amounts
        );
    }

    /// @dev Retrieve or deploy a bridged ERC1155 token contract.
    /// @param ctoken CanonicalNFT data.
    /// @return btoken Address of the bridged token contract.
    function _getOrDeployBridgedToken(CanonicalNFT memory ctoken)
        private
        returns (address btoken)
    {
        btoken = canonicalToBridged[ctoken.chainId][ctoken.addr];
        if (btoken == address(0)) {
            btoken = _deployBridgedToken(ctoken);
        }
    }

    /// @dev Deploy a new BridgedNFT contract and initialize it.
    /// This must be called before the first time a bridged token is sent to
    /// this chain.
    /// @param ctoken CanonicalNFT data.
    /// @return btoken Address of the deployed bridged token contract.
    function _deployBridgedToken(CanonicalNFT memory ctoken)
        private
        returns (address btoken)
    {
        address bridgedToken = Create2Upgradeable.deploy({
            amount: 0, // amount of Ether to send
            salt: keccak256(abi.encode(ctoken)),
            bytecode: type(ProxiedBridgedERC1155).creationCode
        });

        btoken = LibDeploy.deployProxy(
            address(bridgedToken),
            owner(),
            bytes.concat(
                ProxiedBridgedERC1155(bridgedToken).init.selector,
                abi.encode(
                    addressManager,
                    ctoken.addr,
                    ctoken.chainId,
                    ctoken.symbol,
                    ctoken.name
                )
            )
        );
        isBridgedToken[btoken] = true;
        bridgedToCanonical[btoken] = ctoken;
        canonicalToBridged[ctoken.chainId][ctoken.addr] = btoken;
        emit BridgedTokenDeployed({
            chainId: ctoken.chainId,
            ctoken: ctoken.addr,
            btoken: btoken,
            ctokenSymbol: ctoken.symbol,
            ctokenName: ctoken.name
        });
    }
}

/// @title ProxiedERC1155Vault
/// @notice Proxied version of the parent contract.
contract ProxiedERC1155Vault is Proxied, ERC1155Vault { }
