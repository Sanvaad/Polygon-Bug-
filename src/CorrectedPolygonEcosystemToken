// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC20, ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AccessControlEnumerable} from "openzeppelin-contracts/contracts/access/extensions/AccessControlEnumerable.sol";
import {IPolygonEcosystemToken} from "./interface/IPolygonEcosystemToken.sol";
import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

/// @title Polygon ERC20 token
/// @author Polygon Labs (@DhairyaSethi, @gretzke, @qedk, @simonDos)
/// @notice This is the Polygon ERC20 token contract on Ethereum L1
/// @dev The contract allows for a 1-to-1 representation between $POL and $MATIC and allows for additional emission based on hub and treasury requirements
/// @custom:security-contact security@polygon.technology
contract CorrectedPolygonEcosystemToken is ERC20Permit, AccessControlEnumerable, IPolygonEcosystemToken {
    bytes32 public constant EMISSION_ROLE = keccak256("EMISSION_ROLE");
    bytes32 public constant CAP_MANAGER_ROLE = keccak256("CAP_MANAGER_ROLE");
    bytes32 public constant PERMIT2_REVOKER_ROLE = keccak256("PERMIT2_REVOKER_ROLE");
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    uint256 public mintPerSecondCap = 13.37e18;
    uint256 public lastMint;

    // This variable still exists for backward compatibility but no longer
    // affects allowances globally
    bool public permit2Enabled;

    // New mapping to allow users to opt-in to Permit2 max allowance
    mapping(address => bool) public permit2OptIn;

    constructor(address migration, address emissionManager, address protocolCouncil, address emergencyCouncil)
        ERC20("Polygon Ecosystem Token", "POL")
        ERC20Permit("Polygon Ecosystem Token")
    {
        if (
            migration == address(0) || emissionManager == address(0) || protocolCouncil == address(0)
                || emergencyCouncil == address(0)
        ) revert InvalidAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, protocolCouncil);
        _grantRole(EMISSION_ROLE, emissionManager);
        _grantRole(CAP_MANAGER_ROLE, protocolCouncil);
        _grantRole(PERMIT2_REVOKER_ROLE, protocolCouncil);
        _grantRole(PERMIT2_REVOKER_ROLE, emergencyCouncil);
        _mint(migration, 10_000_000_000e18);
        // we can safely set lastMint here since the emission manager is initialised after the token and won't hit the cap.
        lastMint = block.timestamp;

        // Keep this for backward compatibility, but it no longer gives global allowance
        _updatePermit2Allowance(true);
    }

    /// @inheritdoc IPolygonEcosystemToken
    function mint(address to, uint256 amount) external onlyRole(EMISSION_ROLE) {
        uint256 timeElapsedSinceLastMint = block.timestamp - lastMint;
        uint256 maxMint = timeElapsedSinceLastMint * mintPerSecondCap;
        if (amount > maxMint) revert MaxMintExceeded(maxMint, amount);

        lastMint = block.timestamp;
        _mint(to, amount);
    }

    /// @inheritdoc IPolygonEcosystemToken
    function updateMintCap(uint256 newCap) external onlyRole(CAP_MANAGER_ROLE) {
        emit MintCapUpdated(mintPerSecondCap, newCap);
        mintPerSecondCap = newCap;
    }

    /// @inheritdoc IPolygonEcosystemToken
    function updatePermit2Allowance(bool enabled) external onlyRole(PERMIT2_REVOKER_ROLE) {
        _updatePermit2Allowance(enabled);
    }

    /// @notice Allow users to opt in or out of unlimited Permit2 allowance
    /// @param enabled Whether to enable unlimited Permit2 allowance for caller
    function setPermit2OptIn(bool enabled) external {
        permit2OptIn[msg.sender] = enabled;
        emit UserPermit2OptInUpdated(msg.sender, enabled);
    }

    /// @dev Modified to only return max allowance for users who have explicitly opted in
    function allowance(address owner, address spender) public view override(ERC20, IERC20) returns (uint256) {
        // Only return max allowance if all conditions are met:
        // 1. Spender is Permit2
        // 2. Global permit2Enabled flag is true
        // 3. User has specifically opted in
        if (spender == PERMIT2 && permit2Enabled && permit2OptIn[owner]) return type(uint256).max;
        return super.allowance(owner, spender);
    }

    /// @inheritdoc IPolygonEcosystemToken
    function version() external pure returns (string memory) {
        return "1.2.0"; // Version bumped to reflect security enhancement
    }

    function _updatePermit2Allowance(bool enabled) private {
        emit Permit2AllowanceUpdated(enabled);
        permit2Enabled = enabled;
    }

    function nonces(address owner) public view override(ERC20Permit, IERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }

    /// @dev Event emitted when a user updates their Permit2 opt-in status
    event UserPermit2OptInUpdated(address indexed user, bool enabled);
}
