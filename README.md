# 🌾 Crop Yield Prediction Market

A decentralized prediction market built on Stacks where farmers and investors can bet on crop yields, resolved by verified satellite data oracles.

## 📖 Overview

The Crop Yield Prediction Market allows participants to:
- 🚜 **Create Markets**: Set up prediction markets for specific crops, regions, and target yields
- 💰 **Place Bets**: Predict whether actual yields will be higher or lower than targets
- 🛰️ **Oracle Resolution**: Markets resolved using verified satellite data
- 🏆 **Claim Winnings**: Winners receive proportional payouts from the losing side

## 🔧 Core Features

### Market Creation
- Create markets with crop type, region, target yield, and deadline
- Markets automatically close at the specified deadline block height
- Each market has a unique ID for tracking

### Betting System
- Users can bet STX tokens on higher or lower than target yield
- Each user can only place one bet per market
- Bets are locked until market resolution

### Oracle System
- Authorized oracles can resolve markets with actual yield data
- Markets can only be resolved after the deadline
- Resolution triggers the payout calculation system

### Payout Mechanism
- Winners split the losing side's tokens proportionally
- Payouts include original bet amount plus winnings
- Users must manually claim their winnings

## 🚀 Usage Instructions

### For Market Creators

```clarity
;; Create a new market
(contract-call? .Crop-Yield-Prediction-Market create-market 
    "Corn" 
    "Iowa, USA" 
    u150 
    u1000)  ;; deadline block height
```

### For Bettors

```clarity
;; Place a bet (1000 STX on higher yield)
(contract-call? .Crop-Yield-Prediction-Market place-bet 
    u1      ;; market ID
    u1000   ;; amount in microSTX
    true)   ;; bet higher (false for lower)

;; Check potential payout
(contract-call? .Crop-Yield-Prediction-Market calculate-potential-payout 
    u1 u1000 true)
```

### For Oracles

```clarity
;; Resolve market with actual yield
(contract-call? .Crop-Yield-Prediction-Market resolve-market 
    u1    ;; market ID
    u165) ;; actual yield value
```

### For Winners

```clarity
;; Claim winnings after market resolution
(contract-call? .Crop-Yield-Prediction-Market claim-winnings u1)
```

## 📊 Read-Only Functions

### Market Information
```clarity
;; Get market details
(contract-call? .Crop-Yield-Prediction-Market get-market u1)

;; Get market statistics
(contract-call? .Crop-Yield-Prediction-Market get-market-stats u1)

;; Get total market count
(contract-call? .Crop-Yield-Prediction-Market get-market-count)
```

### User Information
```clarity
;; Check user's bet on a market
(contract-call? .Crop-Yield-Prediction-Market get-user-bet 'ST1... u1)
```

### Oracle Information
```clarity
;; Check current oracle
(contract-call? .Crop-Yield-Prediction-Market get-oracle)

;; Verify if address is authorized oracle
(contract-call? .Crop-Yield-Prediction-Market is-oracle 'ST1...)
```

## 🔐 Admin Functions

### Oracle Management
```clarity
;; Set authorized oracle (contract owner only)
(contract-call? .Crop-Yield-Prediction-Market set-oracle 'ST1...)
```

## 🏗️ Contract Architecture

- **Markets**: Store crop type, region, target yield, deadlines, and bet totals
- **User Bets**: Track individual user positions and claim status
- **Oracles**: Manage authorized data providers for market resolution
- **Payouts**: Proportional distribution based on winning/losing pool sizes

## 🛡️ Security Features

- Owner-only oracle authorization
- Single bet per user per market limit
- Market deadline enforcement
- Claim prevention for double spending
- Input validation for all parameters

## 💡 Example Workflow

1. 👨‍🌾 **Farmer creates market**: "Corn yield in Iowa will exceed 150 bushels/acre by block 1000"
2. 💼 **Investors place bets**: Some bet higher, others bet lower with STX tokens
3. ⏰ **Market closes**: No more bets accepted after block 1000
4. 🛰️ **Oracle resolves**: Satellite data shows actual yield was 165 bushels/acre
5. 🎉 **Winners claim**: Those who bet "higher" claim proportional winnings

## 🔍 Error Codes

- `u100`: Owner only operation
- `u101`: Market not found
- `u102`: Already exists (bet/oracle)
- `u103`: Market closed/deadline passed
- `u104`: Insufficient funds
- `u105`: Unauthorized operation
- `u106`: Market already resolved
- `u107`: Invalid amount (zero or negative)

## 📈 Market Statistics

The contract provides real-time statistics including:
- Total betting volume per market
- Percentage breakdown of higher vs lower bets
- Potential payout calculations
- Market resolution status

---

*Built with ❤️ for the agricultural prediction market ecosystem on Stacks blockchain.*
