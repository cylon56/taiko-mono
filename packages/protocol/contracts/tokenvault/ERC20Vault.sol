// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.20;

import { Create2Upgradeable } from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/Create2Upgradeable.sol";
import { ERC20Upgradeable } from
    "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from
    "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { Proxied } from "../common/Proxied.sol";
import { IBridge } from "../bridge/IBridge.sol";
import { LibAddress } from "../libs/LibAddress.sol";
import { LibDeploy } from "../libs/LibDeploy.sol";

import { ProxiedBridgedERC20 } from "./BridgedERC20.sol";
import { IMintableERC20 } from "./IMintableERC20.sol";
import { BaseVault } from "./BaseVault.sol";

/// @title ERC20Vault
/// @dev Labeled in AddressResolver as "erc20_vault"
/// @notice This vault holds all ERC20 tokens (excluding Ether) that users have
/// deposited. It also manages the mapping between canonical ERC20 tokens and
/// their bridged tokens.
contract ERC20Vault is BaseVault {
    using LibAddress for address;
    using SafeERC20Upgradeable for ERC20Upgradeable;

    // Structs for canonical ERC20 tokens and transfer operations
    struct CanonicalERC20 {
        uint64 chainId;
        address addr;
        uint8 decimals;
        string symbol;
        string name;
    }

    struct BridgeTransferOp {
        uint64 destChainId;
        address to;
        address token;
        uint256 amount;
        uint256 gasLimit;
        uint256 fee;
        address refundTo;
        string memo;
    }

    // Tracks if a token on the current chain is a canonical or btoken.
    mapping(address => bool) public isBridgedToken;

    // Mappings from btokens to their canonical tokens.
    mapping(address => CanonicalERC20) public bridgedToCanonical;

    // Mappings from canonical tokens to their btokens. Also storing chainId for
    // tokens across other chains aside from Ethereum.
    mapping(uint256 => mapping(address => address)) public canonicalToBridged;

    uint256[47] private __gap;

    event BridgedTokenDeployed(
        uint256 indexed srcChainId,
        address indexed ctoken,
        address indexed btoken,
        string ctokenSymbol,
        string ctokenName,
        uint8 ctokenDecimal
    );
    event TokenSent(
        bytes32 indexed msgHash,
        address indexed from,
        address indexed to,
        uint64 destChainId,
        address token,
        uint256 amount
    );
    event TokenReleased(
        bytes32 indexed msgHash,
        address indexed from,
        address token,
        uint256 amount
    );
    event TokenReceived(
        bytes32 indexed msgHash,
        address indexed from,
        address indexed to,
        uint64 srcChainId,
        address token,
        uint256 amount
    );

    error VAULT_INVALID_TOKEN();
    error VAULT_INVALID_AMOUNT();
    error VAULT_INVALID_USER();
    error VAULT_INVALID_FROM();
    error VAULT_INVALID_SRC_CHAIN_ID();
    error VAULT_MESSAGE_NOT_FAILED();
    error VAULT_MESSAGE_RELEASED_ALREADY();

    /// @notice Transfers ERC20 tokens to this vault and sends a message to the
    /// destination chain so the user can receive the same amount of tokens by
    /// invoking the message call.
    /// @param op Option for sending ERC20 tokens.
    function sendToken(BridgeTransferOp calldata op)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (IBridge.Message memory _message)
    {
        if (op.amount == 0) revert VAULT_INVALID_AMOUNT();
        if (op.token == address(0)) revert VAULT_INVALID_TOKEN();

        uint256 _amount;
        IBridge.Message memory message;

        (message.data, _amount) = _encodeDestinationCall({
            user: msg.sender,
            token: op.token,
            amount: op.amount,
            to: op.to
        });

        message.destChainId = op.destChainId;
        message.user = msg.sender;
        message.to = resolve(op.destChainId, name(), false);
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
            destChainId: op.destChainId,
            token: op.token,
            amount: _amount
        });
    }

    /// @notice Receive bridged ERC20 tokens and Ether.
    /// @param ctoken Canonical ERC20 data for the token being received.
    /// @param from Source address.
    /// @param to Destination address.
    /// @param amount Amount of tokens being received.
    function receiveToken(
        CanonicalERC20 calldata ctoken,
        address from,
        address to,
        uint256 amount
    )
        external
        payable
        nonReentrant
        whenNotPaused
    {
        IBridge.Context memory ctx = checkProcessMessageContext();
        address _to = to == address(0) || to == address(this) ? from : to;
        address token;

        if (ctoken.chainId == block.chainid) {
            token = ctoken.addr;
            ERC20Upgradeable(token).safeTransfer(_to, amount);
        } else {
            token = _getOrDeployBridgedToken(ctoken);
            IMintableERC20(token).mint(_to, amount);
        }

        _to.sendEther(msg.value);

        emit TokenReceived({
            msgHash: ctx.msgHash,
            from: from,
            to: to,
            srcChainId: ctx.srcChainId,
            token: token,
            amount: amount
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

        (, address token,, uint256 amount) = abi.decode(
            message.data[4:], (CanonicalERC20, address, address, uint256)
        );

        if (token == address(0)) revert VAULT_INVALID_TOKEN();

        if (amount > 0) {
            if (isBridgedToken[token]) {
                IMintableERC20(token).burn(address(this), amount);
            } else {
                ERC20Upgradeable(token).safeTransfer(message.user, amount);
            }
        }

        message.user.sendEther(message.value);

        emit TokenReleased({
            msgHash: msgHash,
            from: message.user,
            token: token,
            amount: amount
        });
    }

    function name() public pure override returns (bytes32) {
        return "erc20_vault";
    }

    /// @dev Encodes sending bridged or canonical ERC20 tokens to the user.
    /// @param user The user's address.
    /// @param token The token address.
    /// @param to To address.
    /// @param amount Amount to be sent.
    /// @return msgData Encoded message data.
    /// @return _balanceChange User token balance actual change after the token
    /// transfer. This value is calculated so we do not assume token balance
    /// change is the amount of token transfered away.
    function _encodeDestinationCall(
        address user,
        address token,
        address to,
        uint256 amount
    )
        private
        returns (bytes memory msgData, uint256 _balanceChange)
    {
        CanonicalERC20 memory ctoken;

        // If it's a bridged token
        if (isBridgedToken[token]) {
            ctoken = bridgedToCanonical[token];
            assert(ctoken.addr != address(0));
            IMintableERC20(token).burn(msg.sender, amount);
            _balanceChange = amount;
        } else {
            // If it's a canonical token
            ERC20Upgradeable t = ERC20Upgradeable(token);
            ctoken = CanonicalERC20({
                chainId: uint64(block.chainid),
                addr: token,
                decimals: t.decimals(),
                symbol: t.symbol(),
                name: t.name()
            });

            uint256 _balance = t.balanceOf(address(this));
            t.transferFrom({
                from: msg.sender,
                to: address(this),
                amount: amount
            });
            _balanceChange = t.balanceOf(address(this)) - _balance;
        }

        msgData = abi.encodeWithSelector(
            ERC20Vault.receiveToken.selector, ctoken, user, to, _balanceChange
        );
    }

    /// @dev Retrieve or deploy a bridged ERC20 token contract.
    /// @param ctoken CanonicalERC20 data.
    /// @return btoken Address of the bridged token contract.
    function _getOrDeployBridgedToken(CanonicalERC20 calldata ctoken)
        private
        returns (address btoken)
    {
        btoken = canonicalToBridged[ctoken.chainId][ctoken.addr];

        if (btoken == address(0)) {
            btoken = _deployBridgedToken(ctoken);
        }
    }

    /// @dev Deploy a new BridgedERC20 contract and initialize it.
    /// This must be called before the first time a bridged token is sent to
    /// this chain.
    /// @param ctoken CanonicalERC20 data.
    /// @return btoken Address of the deployed bridged token contract.
    function _deployBridgedToken(CanonicalERC20 calldata ctoken)
        private
        returns (address btoken)
    {
        address bridgedToken = Create2Upgradeable.deploy({
            amount: 0, // amount of Ether to send
            salt: keccak256(abi.encode(ctoken)),
            bytecode: type(ProxiedBridgedERC20).creationCode
        });

        btoken = LibDeploy.deployProxy(
            address(bridgedToken),
            owner(),
            bytes.concat(
                ProxiedBridgedERC20(bridgedToken).init.selector,
                abi.encode(
                    addressManager,
                    ctoken.addr,
                    ctoken.chainId,
                    ctoken.decimals,
                    ctoken.symbol,
                    ctoken.name
                )
            )
        );

        isBridgedToken[btoken] = true;
        bridgedToCanonical[btoken] = ctoken;
        canonicalToBridged[ctoken.chainId][ctoken.addr] = btoken;

        emit BridgedTokenDeployed({
            srcChainId: ctoken.chainId,
            ctoken: ctoken.addr,
            btoken: btoken,
            ctokenSymbol: ctoken.symbol,
            ctokenName: ctoken.name,
            ctokenDecimal: ctoken.decimals
        });
    }
}

/// @title ProxiedERC20Vault
/// @notice Proxied version of the parent contract.
contract ProxiedERC20Vault is Proxied, ERC20Vault { }
