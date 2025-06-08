# AIDebate Refund System Documentation

## Table of Contents
1. [Overview](#overview)
2. [Core Concepts](#core-concepts)
3. [Refund Functions](#refund-functions)
4. [Query Functions](#query-functions)
5. [Usage Examples](#usage-examples)
6. [Integration Guide](#integration-guide)
7. [Edge Cases & Important Notes](#edge-cases--important-notes)

## Overview

The AIDebate smart contract includes a comprehensive refund system that allows administrators to mark debates as refundable and enables users to recover their bet amounts when debates cannot be properly resolved. This feature ensures fairness and provides a safety mechanism for unexpected situations.

### Key Features
- **Admin-controlled refund marking**: Only moderators can mark debates as refundable
- **Flexible refund processing**: Both admin-initiated and user-initiated refunds
- **Complete bet recovery**: Users can recover the full amount of their bets
- **Comprehensive query system**: Multiple functions to check refund status and amounts
- **Event-driven architecture**: All refund actions emit events for tracking

## Core Concepts

### Refund States
A debate can be in one of these states regarding refunds:
- **Normal**: Standard debate flow, refunds not available
- **Refundable**: Admin has marked the debate for refunds, users can claim their bets back
- **Resolved**: Debate has a winner, refunds are no longer possible

### User Refund Status
Each user's refund status is tracked per bet:
- **Not Refunded**: User hasn't claimed or received refund for this bet
- **Refunded**: User has successfully received refund for this bet
- **Claimed**: User has claimed winnings (prevents refund)

## Refund Functions

### Admin Functions

#### `adminMarkDebateRefundable(uint256 _debateId)`
Marks a debate as refundable, allowing users to claim refunds instead of waiting for resolution.

**Requirements:**
- Only callable by moderators (`onlyMod`)
- Debate must exist (have agents assigned)
- Debate must not be already resolved
- Debate must not be already marked as refundable

**Events:** Emits `DebateMarkedRefundable(debateId)`

```solidity
// Example usage
await contract.connect(moderator).adminMarkDebateRefundable(1);
```

#### `adminProcessRefunds(uint256 _debateId)`
Processes refunds for all users who bet on a refundable debate. This is a bulk operation that refunds all eligible bets.

**Requirements:**
- Only callable by moderators (`onlyMod`)
- Debate must be marked as refundable
- Debate must not be resolved
- Sufficient contract balance for all refunds

**Events:** Emits `UserRefunded(debateId, bettor, amount)` for each processed refund

```solidity
// Example usage - refunds all users automatically
await contract.connect(moderator).adminProcessRefunds(1);
```

### User Functions

#### `userRefund(uint256 _debateId)`
Allows individual users to claim their refunds for a debate marked as refundable.

**Requirements:**
- Debate must be marked as refundable
- Debate must not be resolved
- User must have placed bets on the debate
- User must have unclaimed, unrefunded bets
- Sufficient contract balance

**Features:**
- Processes all eligible bets for the user in a single transaction
- Handles both agent A and agent B bets
- Prevents double refunds
- Emits separate events for each bet refunded

```solidity
// Example usage
await contract.connect(user).userRefund(1);
```

## Query Functions

### `getUsersRefundInfo(uint256 _debateId)` 🎯 **Primary Frontend Function**

Returns comprehensive refund information for all users who participated in a debate.

**Function Signature:**
```solidity
function getUsersRefundInfo(uint256 _debateId) external view returns (UserRefundInfo[] memory)
```

**Return Structure:**
```solidity
struct UserRefundInfo {
    address user;           // User's wallet address
    uint256 amountOfRefund; // Total bet amount (refundable amount)
    bool refunded;          // True if ALL user's bets are refunded
}
```

**Key Features:**
- Returns data for ALL users who bet on the debate
- `amountOfRefund` is the sum of all bets (agent A + agent B)
- `refunded` is true only when ALL user's bets are refunded
- Works regardless of debate state (refundable, resolved, or normal)

### `getUserRefundableAmount(uint256 _debateId, address _user)`

Returns the refundable amount for a specific user.

**Function Signature:**
```solidity
function getUserRefundableAmount(uint256 _debateId, address _user) external view returns (uint256)
```

**Behavior:**
- Returns 0 if debate is not refundable
- Returns 0 if debate is resolved
- Returns total unclaimed, unrefunded bet amount for the user
- Returns 0 if user has no eligible bets

### `isDebateRefundable(uint256 _debateId)`

Simple check to see if a debate is marked as refundable.

```solidity
function isDebateRefundable(uint256 _debateId) external view returns (bool)
```

### `getUserRefundStatus(uint256 _debateId, address _user, uint _agentId)`

Get refund status for a specific bet.

```solidity
function getUserRefundStatus(uint256 _debateId, address _user, uint _agentId) 
    external view returns (bool isRefunded, uint256 amount)
```

## Usage Examples

### Complete Frontend Integration

```javascript
// Check if debate is refundable
const isRefundable = await contract.isDebateRefundable(debateId);

if (isRefundable) {
    // Get all users' refund information
    const refundInfo = await contract.getUsersRefundInfo(debateId);
    
    // Display refund dashboard
    console.log("=== Refund Status Dashboard ===");
    refundInfo.forEach(userInfo => {
        console.log(`User: ${userInfo.user}`);
        console.log(`Total Bet: ${ethers.formatEther(userInfo.amountOfRefund)} ETH`);
        console.log(`Status: ${userInfo.refunded ? '✅ Refunded' : '❌ Pending'}`);
        console.log("---");
    });
    
    // Find users who still need refunds
    const pendingRefunds = refundInfo.filter(info => !info.refunded);
    console.log(`Users pending refund: ${pendingRefunds.length}`);
    
    // Calculate total pending refund amount
    const totalPending = pendingRefunds.reduce(
        (sum, info) => sum + info.amountOfRefund, 0n
    );
    console.log(`Total pending amount: ${ethers.formatEther(totalPending)} ETH`);
}
```

### Admin Refund Processing

```javascript
// Mark debate as refundable
await contract.connect(moderator).adminMarkDebateRefundable(debateId);
console.log("Debate marked as refundable");

// Option 1: Process all refunds at once
await contract.connect(moderator).adminProcessRefunds(debateId);
console.log("All refunds processed");

// Option 2: Let users claim individually
// (No additional admin action needed)
```

### User Claiming Refunds

```javascript
// Check user's refundable amount
const userAddress = await signer.getAddress();
const refundableAmount = await contract.getUserRefundableAmount(debateId, userAddress);

if (refundableAmount > 0) {
    console.log(`You can claim: ${ethers.formatEther(refundableAmount)} ETH`);
    
    // Claim refund
    const tx = await contract.connect(user).userRefund(debateId);
    await tx.wait();
    console.log("Refund claimed successfully!");
}
```

### Building a Refund Component

```javascript
// React component example
const RefundComponent = ({ debateId }) => {
    const [refundInfo, setRefundInfo] = useState([]);
    const [isRefundable, setIsRefundable] = useState(false);
    
    useEffect(() => {
        const loadRefundData = async () => {
            const refundable = await contract.isDebateRefundable(debateId);
            setIsRefundable(refundable);
            
            const info = await contract.getUsersRefundInfo(debateId);
            setRefundInfo(info);
        };
        
        loadRefundData();
    }, [debateId]);
    
    const handleUserRefund = async () => {
        try {
            const tx = await contract.connect(signer).userRefund(debateId);
            await tx.wait();
            // Refresh data
            loadRefundData();
        } catch (error) {
            console.error("Refund failed:", error);
        }
    };
    
    return (
        <div>
            <h3>Refund Status</h3>
            {isRefundable ? (
                <div>
                    <p>✅ This debate is refundable</p>
                    <button onClick={handleUserRefund}>Claim My Refund</button>
                    
                    <table>
                        <thead>
                            <tr>
                                <th>User</th>
                                <th>Amount</th>
                                <th>Status</th>
                            </tr>
                        </thead>
                        <tbody>
                            {refundInfo.map(info => (
                                <tr key={info.user}>
                                    <td>{info.user}</td>
                                    <td>{ethers.formatEther(info.amountOfRefund)} ETH</td>
                                    <td>{info.refunded ? "✅" : "❌"}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            ) : (
                <p>❌ This debate is not refundable</p>
            )}
        </div>
    );
};
```

## Integration Guide

### Step 1: Check Refund Availability
```javascript
const isRefundable = await contract.isDebateRefundable(debateId);
```

### Step 2: Get User Information
```javascript
// For all users
const allUsersInfo = await contract.getUsersRefundInfo(debateId);

// For specific user
const userAmount = await contract.getUserRefundableAmount(debateId, userAddress);
```

### Step 3: Process Refunds
```javascript
// Admin processing (all at once)
await contract.connect(moderator).adminProcessRefunds(debateId);

// User processing (individual)
await contract.connect(user).userRefund(debateId);
```

### Step 4: Listen for Events
```javascript
// Listen for refund events
contract.on("UserRefunded", (debateId, bettor, amount, event) => {
    console.log(`User ${bettor} refunded ${ethers.formatEther(amount)} ETH`);
});

contract.on("DebateMarkedRefundable", (debateId, event) => {
    console.log(`Debate ${debateId} is now refundable`);
});
```

## Edge Cases & Important Notes

### Refund Logic
1. **Full Refund Only**: Users get back exactly what they bet, no fees deducted
2. **Prevents Double Refund**: Contract ensures each bet can only be refunded once
3. **No Partial Refunds**: Users either get full refund or nothing
4. **All Bets Included**: Both agent A and agent B bets are refundable

### State Transitions
```
Normal Debate → Refundable → [Refunds Processed]
            ↘ Resolved (refunds no longer possible)
```

### Important Considerations
- **Contract Balance**: Ensure contract has sufficient ETH for refunds
- **Gas Costs**: `adminProcessRefunds` can be expensive for many users
- **User Experience**: `userRefund` is more gas-efficient for individual users
- **Event Tracking**: Use events to build comprehensive refund history
- **Error Handling**: Always handle insufficient balance and other edge cases

### Security Features
- **Access Control**: Only moderators can mark debates as refundable
- **State Validation**: Multiple checks prevent invalid refund attempts
- **Reentrancy Protection**: Uses `.transfer()` which limits gas and prevents reentrancy
- **Balance Checks**: Verifies sufficient contract balance before transfers

### Gas Optimization Tips
1. Use `getUsersRefundInfo` for frontend display (view function, no gas)
2. Batch refund processing with `adminProcessRefunds` when possible
3. Let users claim individually with `userRefund` for better UX
4. Cache refund status in frontend to minimize contract calls

---

This refund system provides a robust, secure, and user-friendly way to handle debate cancellations and dispute resolutions while maintaining the integrity of the betting mechanism.
