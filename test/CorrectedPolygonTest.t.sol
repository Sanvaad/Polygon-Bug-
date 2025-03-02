// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {CorrectedPolygonEcosystemToken} from "../src/CorrectedPolygonEcosystemToken.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Mock Permit2 contract with just enough implementation to demonstrate the fix
contract MockPermit2 {
    function transferFrom(address token, address from, address to, uint256 amount) external {
        IERC20(token).transferFrom(from, to, amount);
    }
}

contract CorrectedPolygonTest is Test {
    CorrectedPolygonEcosystemToken polToken;
    MockPermit2 permit2;

    address migration = address(0x1);
    address emissionManager = address(0x2);
    address protocolCouncil = address(0x3);
    address emergencyCouncil = address(0x4);

    address victim = address(0x5);
    address attacker = address(0x6);

    function setUp() public {
        // Deploy our mock Permit2 at the exact same address as in the contract
        address permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

        // Use vm.etch to deploy our mock implementation at the specific address
        vm.etch(permit2Address, address(new MockPermit2()).code);
        permit2 = MockPermit2(permit2Address);

        // Deploy the token with the constructor parameters
        vm.startPrank(migration);
        polToken = new CorrectedPolygonEcosystemToken(migration, emissionManager, protocolCouncil, emergencyCouncil);

        // Fund victim with tokens
        polToken.transfer(victim, 1000e18);
        vm.stopPrank();

        // Verify initial setup
        console.log("Victim balance:", polToken.balanceOf(victim));
        console.log("Attacker balance:", polToken.balanceOf(attacker));

        // Check that permit2Enabled is true (set in constructor)
        assertTrue(polToken.permit2Enabled(), "Permit2 should be enabled by default");
    }

    function testSecureByDefault() public {
        // Show that victim has never approved any transfers
        // We'll check using the internal mapping via storage inspection
        bytes32 slot = keccak256(
            abi.encode(
                victim,
                keccak256(abi.encode(polToken.PERMIT2(), uint256(0))) // allowance slot in ERC20
            )
        );
        uint256 actualAllowance = uint256(vm.load(address(polToken), slot));
        console.log("Actual storage allowance for Permit2:", actualAllowance);
        assertEq(actualAllowance, 0, "Victim has not explicitly approved anything for Permit2");

        // Check victim's opt-in status (should be false by default)
        assertFalse(polToken.permit2OptIn(victim), "User should not be opted in by default");

        // Check that allowance is zero despite permit2Enabled being true
        uint256 permit2Allowance = polToken.allowance(victim, polToken.PERMIT2());
        console.log("Permit2 allowance reported by contract:", permit2Allowance);
        assertEq(permit2Allowance, 0, "Permit2 allowance should be 0 when user has not opted in");

        // Try to exploit - should fail now
        vm.prank(attacker);
        vm.expectRevert();
        permit2.transferFrom(address(polToken), victim, attacker, 1000e18);

        // Verify balances unchanged
        assertEq(polToken.balanceOf(victim), 1000e18, "Victim balance should be unchanged");
        assertEq(polToken.balanceOf(attacker), 0, "Attacker should not have tokens");
    }

    function testOptIn() public {
        // User opts in to Permit2
        vm.prank(victim);
        polToken.setPermit2OptIn(true);

        // Verify opt-in status
        assertTrue(polToken.permit2OptIn(victim), "User should be opted in");

        // Check that allowance now returns max value
        uint256 permit2Allowance = polToken.allowance(victim, polToken.PERMIT2());
        assertEq(permit2Allowance, type(uint256).max, "Permit2 allowance should be max after opt-in");

        // Now the transfer should work
        vm.prank(attacker);
        permit2.transferFrom(address(polToken), victim, attacker, 1000e18);

        // Verify transfer was successful
        assertEq(polToken.balanceOf(victim), 0, "Victim opted in, so transfer should work");
        assertEq(polToken.balanceOf(attacker), 1000e18, "Attacker should have tokens after victim opt-in");
    }

    function testOptOut() public {
        // First opt in
        vm.prank(victim);
        polToken.setPermit2OptIn(true);

        // Verify permit2 has allowance
        assertEq(
            polToken.allowance(victim, polToken.PERMIT2()), type(uint256).max, "Allowance should be max after opt-in"
        );

        // Now opt out
        vm.prank(victim);
        polToken.setPermit2OptIn(false);

        // Verify allowance is now zero
        assertEq(polToken.allowance(victim, polToken.PERMIT2()), 0, "Allowance should be zero after opt-out");

        // Try to transfer - should fail
        vm.prank(attacker);
        vm.expectRevert();
        permit2.transferFrom(address(polToken), victim, attacker, 1000e18);

        // Verify balances unchanged
        assertEq(polToken.balanceOf(victim), 1000e18, "Victim balance should be unchanged after opt-out");
        assertEq(polToken.balanceOf(attacker), 0, "Attacker should not have tokens after victim opt-out");
    }

    function testDisabledPermit2() public {
        // First user opts in
        vm.prank(victim);
        polToken.setPermit2OptIn(true);

        // Verify opt-in works
        assertTrue(polToken.permit2OptIn(victim), "User should be opted in");
        assertEq(
            polToken.allowance(victim, polToken.PERMIT2()), type(uint256).max, "Allowance should be max after opt-in"
        );

        // Now admin disables Permit2
        vm.prank(protocolCouncil);
        polToken.updatePermit2Allowance(false);

        // Verify Permit2 is disabled
        assertFalse(polToken.permit2Enabled(), "Permit2 should be disabled");

        // Check that allowance is zero even though user opted in
        assertEq(
            polToken.allowance(victim, polToken.PERMIT2()),
            0,
            "Permit2 allowance should be 0 when disabled, even if user opted in"
        );

        // Try to exploit - should fail
        vm.prank(attacker);
        vm.expectRevert();
        permit2.transferFrom(address(polToken), victim, attacker, 1000e18);

        // Verify balances unchanged
        assertEq(polToken.balanceOf(victim), 1000e18, "Victim balance should be unchanged when Permit2 disabled");
        assertEq(polToken.balanceOf(attacker), 0, "Attacker should not have tokens when Permit2 disabled");
    }

    function testOptInAfterDisabled() public {
        // Admin disables Permit2
        vm.prank(protocolCouncil);
        polToken.updatePermit2Allowance(false);

        // User tries to opt in
        vm.prank(victim);
        polToken.setPermit2OptIn(true);

        // Verify opt-in state
        assertTrue(polToken.permit2OptIn(victim), "User should be marked as opted in");

        // But allowance should still be zero due to global disable
        assertEq(
            polToken.allowance(victim, polToken.PERMIT2()),
            0,
            "Allowance should be zero when Permit2 is disabled globally, regardless of opt-in"
        );
    }
}
