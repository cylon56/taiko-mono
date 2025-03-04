// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.20;

import { Create2Upgradeable } from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/Create2Upgradeable.sol";
import {
    ERC721Upgradeable,
    IERC721Upgradeable
} from
    "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import { IERC721ReceiverUpgradeable } from
    "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/IERC721ReceiverUpgradeable.sol";

import { IBridge } from "../bridge/IBridge.sol";
import { LibAddress } from "../libs/LibAddress.sol";
import { LibDeploy } from "../libs/LibDeploy.sol";
import { Proxied } from "../common/Proxied.sol";

import { BaseNFTVault } from "./BaseNFTVault.sol";
import { ProxiedBridgedERC721 } from "./BridgedERC721.sol";

/// @title ERC721Vault
/// @dev Labeled in AddressResolver as "erc721_vault"
/// @notice This vault holds all ERC721 tokens that users have deposited.
/// It also manages the mapping between canonical tokens and their bridged
/// tokens.
contract ERC721Vault is BaseNFTVault, IERC721ReceiverUpgradeable {
    using LibAddress for address;

    uint256[50] private __gap;

    /// @notice Transfers ERC721 tokens to this vault and sends a message to the
    /// destination chain so the user can receive the same (bridged) tokens
    /// by invoking the message call.
    /// @param op Option for sending the ERC721 token.
    function sendToken(BridgeTransferOp calldata op)
        external
        payable
        nonReentrant
        whenNotPaused
        whenOperationValid(op)
        returns (IBridge.Message memory _message)
    {
        for (uint256 i; i < op.tokenIds.length; ++i) {
            if (op.amounts[i] != 0) revert VAULT_INVALID_AMOUNT();
        }

        if (!op.token.supportsInterface(ERC721_INTERFACE_ID)) {
            revert VAULT_INTERFACE_NOT_SUPPORTED();
        }

        // We need to save them into memory - because structs containing
        // dynamic arrays will cause stack-too-deep error when passed
        uint256[] memory _amounts = op.amounts;
        address _token = op.token;
        uint256[] memory _tokenIds = op.tokenIds;

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

        bytes32 msgHash;
        (msgHash, _message) = IBridge(resolve("bridge", false)).sendMessage{
            value: msg.value
        }(message);

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

    /// @notice Receive bridged ERC721 tokens and handle them accordingly.
    /// @param ctoken Canonical NFT data for the token being received.
    /// @param from Source address.
    /// @param to Destination address.
    /// @param tokenIds Array of token IDs being received.
    function receiveToken(
        CanonicalNFT calldata ctoken,
        address from,
        address to,
        uint256[] memory tokenIds
    )
        external
        payable
        nonReentrant
        whenNotPaused
    {
        IBridge.Context memory ctx = checkProcessMessageContext();

        address _to = to == address(0) || to == address(this) ? from : to;
        address token;

        unchecked {
            if (ctoken.chainId == block.chainid) {
                token = ctoken.addr;
                for (uint256 i; i < tokenIds.length; ++i) {
                    ERC721Upgradeable(token).transferFrom({
                        from: address(this),
                        to: _to,
                        tokenId: tokenIds[i]
                    });
                }
            } else {
                token = _getOrDeployBridgedToken(ctoken);
                for (uint256 i; i < tokenIds.length; ++i) {
                    ProxiedBridgedERC721(token).mint(_to, tokenIds[i]);
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
            amounts: new uint256[](0)
        });
    }

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

        if (message.user == address(0)) revert VAULT_INVALID_USER();
        if (message.srcChainId != block.chainid) {
            revert VAULT_INVALID_SRC_CHAIN_ID();
        }

        (CanonicalNFT memory nft,,, uint256[] memory tokenIds) = abi.decode(
            message.data[4:], (CanonicalNFT, address, address, uint256[])
        );

        if (nft.addr == address(0)) revert VAULT_INVALID_TOKEN();

        unchecked {
            if (isBridgedToken[nft.addr]) {
                for (uint256 i; i < tokenIds.length; ++i) {
                    ProxiedBridgedERC721(nft.addr).mint(
                        message.user, tokenIds[i]
                    );
                }
            } else {
                for (uint256 i; i < tokenIds.length; ++i) {
                    IERC721Upgradeable(nft.addr).safeTransferFrom({
                        from: address(this),
                        to: message.user,
                        tokenId: tokenIds[i]
                    });
                }
            }
        }

        // send back Ether
        message.user.sendEther(message.value);

        emit TokenReleased({
            msgHash: msgHash,
            from: message.user,
            token: nft.addr,
            tokenIds: tokenIds,
            amounts: new uint256[](0)
        });
    }

    /// @inheritdoc IERC721ReceiverUpgradeable
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    )
        external
        pure
        returns (bytes4)
    {
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }

    function name() public pure override returns (bytes32) {
        return "erc721_vault";
    }

    /// @dev Encodes sending bridged or canonical ERC721 tokens to the user.
    /// @param user The user's address.
    /// @param op BridgeTransferOp data.
    /// @return msgData Encoded message data.
    function _encodeDestinationCall(
        address user,
        BridgeTransferOp calldata op
    )
        private
        returns (bytes memory msgData)
    {
        CanonicalNFT memory nft;

        unchecked {
            if (isBridgedToken[op.token]) {
                nft = bridgedToCanonical[op.token];
                for (uint256 i; i < op.tokenIds.length; ++i) {
                    ProxiedBridgedERC721(op.token).burn(user, op.tokenIds[i]);
                }
            } else {
                ERC721Upgradeable t = ERC721Upgradeable(op.token);

                nft = CanonicalNFT({
                    chainId: uint64(block.chainid),
                    addr: op.token,
                    symbol: t.symbol(),
                    name: t.name()
                });

                for (uint256 i; i < op.tokenIds.length; ++i) {
                    t.transferFrom(user, address(this), op.tokenIds[i]);
                }
            }
        }

        msgData = abi.encodeWithSelector(
            ERC721Vault.receiveToken.selector, nft, user, op.to, op.tokenIds
        );
    }

    /// @dev Retrieve or deploy a bridged ERC721 token contract.
    /// @param ctoken CanonicalNFT data.
    /// @return btoken Address of the bridged token contract.
    function _getOrDeployBridgedToken(CanonicalNFT calldata ctoken)
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
            bytecode: type(ProxiedBridgedERC721).creationCode
        });

        btoken = LibDeploy.deployProxy(
            address(bridgedToken),
            owner(),
            bytes.concat(
                ProxiedBridgedERC721(bridgedToken).init.selector,
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

/// @title ProxiedERC721Vault
/// @notice Proxied version of the parent contract.
contract ProxiedERC721Vault is Proxied, ERC721Vault { }
