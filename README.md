# Polygon POL Token Security Vulnerability

This repo shows a critical security issue in the POL token implementation. The issue is with the Permit2 allowance override in the contract.

## Setup

You'll need Foundry to run these tests. If you don't have it, then install itt:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

## How to run

Cloner this repo:
```bash
git clone https://github.com/Sanvaad/Polygon-Bug-
cd pol-vulnerability
```

Install dependencies:
```bash
forge install
```

Run the tests:
```bash
forge test -vv
```

## What this proves

The tests in `POLExploitTest.t.sol` show that:

1. The POL token gives unlimited allowance to Permit2 for ALL users
2. Normal ERC20 transfers require approval (see `testNormalAllowance`)
3. Permit2 can drain ANY user tokens without their permission (see `testPermit2Vulnerability`)
4. The exploit is stopped when Permit2 is disabled (see `testDisabledPermit2`)

## The vulnerability

The problem is in the `allowance()` function:

```solidity
function allowance(address owner, address spender) public view override(ERC20, IERC20) returns (uint256) {
    if (spender == PERMIT2 && permit2Enabled) return type(uint256).max;
    return super.allowance(owner, spender);
}
```

This gives Permit2 contract unlimited allowance for EVERYONE'S tokens - whether they want it or not. This is dangerous because:

1. Users never explicitly approve this
2. The actual allowance in storage is 0 (we check this in the test)
3. But the contract LIES and returns max uint256 when Permit2 asks
4. If Permit2 has ANY bugs or is compromised, all user funds are at risk

## How the exploit works

1. The test deploys a mock Permit2 at the exact address hardcoded in the POL token
2. It checks the actual allowance in storage (it's 0)
3. It checks what allowance() returns (it's max uint256)
4. Then it calls Permit2.transferFrom() which successfully drains the user's tokens
5. This works even though the user NEVER approved any allowance

## Fix

The solution is to remove the allowance override completely OR make it opt-in for each user.

To see the issue in detail, look at the `testPermit2Vulnerability()` function in the test contract.

I have given the corrected version 
in it i - 

-Added a user opt-in system-
mapping(address => bool) public permit2OptIn;

-Added a function for users to control their own opt-in status:-
function setPermit2OptIn(bool enabled) external {
    permit2OptIn[msg.sender] = enabled;
    emit UserPermit2OptInUpdated(msg.sender, enabled);
}

-Modified the allowance function to require explicit user consent:-

function allowance(address owner, address spender) public view override(ERC20, IERC20) returns (uint256) {
    // Only return max allowance if all conditions are met:
    // 1. Spender is Permit2
    // 2. Global permit2Enabled flag is true
    // 3. User has specifically opted in
    if (spender == PERMIT2 && permit2Enabled && permit2OptIn[owner]) return type(uint256).max;
    return super.allowance(owner, spender);
}

-Added a new event to track opt-in status changes:-
event UserPermit2OptInUpdated(address indexed user, bool enabled);


-Updated the version number to reflect the security improvement:-
function version() external pure returns (string memory) {
    return "1.2.0"; // Version bumped to reflect security enhancement
}




## Results

When running the tests, you'll see output like:

```
Logs:
  Victim balance: 1000000000000000000000
  Attacker balance: 0
  Actual storage allowance for Permit2: 0
  Permit2 allowance reported by contract: 115792089237316195423570985008687907853269984665640564039457584007913129639935
  Executing attack...
  Victim balance after attack: 0
  Attacker balance after attack: 1000000000000000000000
```

This proves the victim's tokens are stolen without their approval.
