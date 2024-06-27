Updated May 29, 2024

Change owner: Raul Jordan

# Solidity Interface

```solidity
pragma solidity ^0.8.13;

/// @notice a bid used for express lane auctions.
/// @param chainId     the chain id of the target chain.
/// @param round       the round number for which the bid is made.
/// @param bid         the amount of bid.
/// @param signature   an ecdsa signature by the bidder’s private key 
///                    on the abi encoded tuple 
///                    (uint16 domainValue, uint64 chainId, uint64 roundNumber, uint256 amount)
///                    where domainValue is a constant used for domain separation.
struct Bid {
    uint256 chainId;
    uint256 round;
    uint256 amount;
    bytes signature;
}

interface IExpressLaneAuction {
    /// @notice An ERC-20 token deposit is made to the auction contract.
    /// @param bidder the address of the bidder
    /// @param amount    the amount in wei of the deposit
    event DepositSubmitted(address indexed bidder, uint256 amount);

    /// @notice An ERC-20 token withdrawal request is made to the auction contract.
    /// @param bidder the address of the bidder
    /// @param amount    the amount in wei requested to be withdrawn
    event WithdrawalInitiated(address indexed bidder, uint256 amount);

    /// @notice An existing withdrawal request is completed and the funds are transferred.
    /// @param bidder the address of the bidder
    /// @param amount    the amount in wei withdrawn
    event WithdrawalFinalized(address indexed bidder, uint256 amount);

    /// @notice An auction is resolved and a winner is declared as the express 
    ///         lane controller for a round number.
    /// @param winningBidAmount  the amount in wei of the winning bid
    /// @param loserBidAmount    the amount in wei of the second-highest bid
    /// @param winningBidder     the address of the winner and designated express lane controller
    /// @param winnerRound       the round number for which the winner will be the express lane controller
    event AuctionResolved(
        uint256 winningBidAmount, 
        uint256 loserBidAmount,
        address indexed winningBidder,
        uint256 indexed winnerRound
    );

    /// @notice Control of the upcoming round's express lane was delegated to another address.
    /// @param from the winner of the express lane that decided to delegate control to another.
    /// @param to   the new address in control of the express lane for a round.
    event ExpressLaneControlDelegated(
        address indexed from,
        address indexed to,
        uint64 round
    );

    /// @notice Fetches the reserved address for the express lane, used by the
    ///         express lane controller to submit their transactions to the sequencer
    ///         by setting the "to" field of their transactions to this address.
    /// @return the reserved address
    function expressLaneAddress() external view returns (address);

    /// @notice Once the auctioneer resolves an auction, it will deduct the second-highest
    ///         bid amount from the account of the highest bidder and transfer those funds
    ///         to either an address designated by governance, or burn them to the zero address.
    ///         This function will return the address to which the funds are transferred or zero
    ///         if funds are burnt.
    /// @return the address to which the funds are transferred or zero if funds are burnt.
    function bidReceiver() external view returns (address);

    /// @notice Gets the address of the current express lane controller, which has
    ///         won the auction for the current round. Will return the zero address
    ///         if there is no current express lane controller set.
    ///         the current round number can be determined offline by using the round duration
    ///         seconds and the initial round timestamp of the contract.
    /// @return the address of the current express lane controller
    function currentExpressLaneController() external view returns (address);

    /// @notice Gets the duration of each round in seconds
    /// @return the round duration seconds
    function roundDurationSeconds() external view returns (uint64);

    /// @notice Gets the initial round timestamp for the auction contract
    ///         round timestamps should be a multiple of the round duration seconds
    ///         for convenience.
    /// @return the initial round timestamp
    function initialRoundTimestamp() external view returns (uint256);

    /// @notice Gets the balance of a bidder in the contract.
    /// @param bidder the address of the bidder.
    /// @return the balance of the bidder in the contract.
    function bidderBalance(address bidder) external view returns (uint256);

    /// @notice Gets the domain value required for the signature of a bid, which is a domain
    ///         separator constant used for signature verification.
    ///         bids contain a signature over an abi encoded tuple of the form
    ///         (uint16 domainValue, uint64 chainId, uint64 roundNumber, uint256 amount)
    /// @return the domain value required for bid signatures.
    function bidSignatureDomainValue() external view returns (uint16);

    /// @notice Deposits an ERC-20 token amount ino the auction contract.
    ///         The sender can deposit into the contract at any time.
    /// @param amount the amount to deposit.
    function submitDeposit(uint256 amount) external;

    /// @notice Initiates a withdrawal for part or all of a sender's deposited funds.
    ///         This request can be submitted at any time, but a withdrawal submitted
    ///         at round i can only be claimed by the party at the beginning of round i+2.
    /// @param amount the amount to withdrawal.
    function initiateWithdrawal(uint256 amount) external;

    /// @notice Claims a withdrawal. This function will revert is there was no withdrawal
    ///         initiated by the specified bidder at around i-2, where the current round is i.
    function finalizeWithdrawal(uint256 amount) external;

    /// @notice Only the auctioneer can call this method. If there are only two distinct bids
    ///         present for bidding on the upcoming round, the round can be deemed canceled by setting
    ///         the express lane controller to the zero address.
    function cancelUpcomingRound() external;

    /// @notice Allows the upcoming round's express lane controller to delegate ownership of the express lane
    ///         to a delegate address. Can only be called after an auction has resolved and before the upcoming
    ///         round begins, and the sender must be the winner of the latest resolved auction. Will update
    ///         the express lane controller for the upcoming round to the specified delegate address.
    /// @param delegate the address to delegate the upcoming round to.
    function delegateExpressLane(address delegate) external;

    /// @notice Only the auctioneer can call this method, passing in the two highest bids.
    ///         The auction contract will verify the signatures on these bids,
    ///         and that both are backed by funds deposited in the auction contract.
    ///         Then the auction contract will deduct the second-highest bid amount
    ///         from the account of the highest bidder, and transfer those funds to
    ///         an account designated by governance, or burn them if governance
    ///         specifies that the proceeds are to be burned.
    ///         auctions are resolved by the auctioneer before the end of a current round
    ///         at some time T = AUCTION_CLOSING_SECONDS where T < ROUND_DURATION_SECONDS.
    /// @param bid1 the first bid
    /// @param bid2 the second bid
    function resolveAuction(Bid calldata bid1, Bid calldata bid2) external;
}
```

# Offchain Components

## Auctioneer API

The auctioneer must expose a new RPC namespace called `timeboost` and a RPC method called `timeboost_submitBid`

### `timeboost_submitBid`

```json
{
  "type": "object",
  "properties": {
    "chain_id": {
      "type": "uint64",
      "description": "chain id of the target chain"
    },
    "address": {
      "type": "string",
      "description": "0x-prefixed, 20-byte address of the bidder"
    },
    "round": {
      "type": "uint64",
      "description": "round number (0-indexed) for the round being bid on"
    },
    "amount": {
      "type": "uint256",
      "description": "The amount in wei of the deposit ERC-20 to bid"
    },
    "signature": {
      "type": "string",
      "description": "0x-prefixed ECDSA signature of an ABI encoded tuple (domainValue, chainId, round, amount)"
    }
  },
  "required": ["chain_id", "address", "round", "amount", "signature"]
}
```

The auctioneer will perform the following validation:

- Check if the chain id is correct
- Check if the round number is for the upcoming round only
- Check if the sender is a depositor in the contract
- Check the sender has enough balance to make that bid and that the amount is non-zero
- Verify the signature

Then, the auctioneer will respond with:

```json
{
  "type": "object",
  "properties": {
    "status": {
      "type": "string",
      "enum": ["ERROR", "OK"],
      "description": "Indicates the response from receiving a new bid."
    },
    "error": {
      "type": "string",
      "enum": ["MALFORMED_DATA", "NOT_DEPOSITOR", "WRONG_CHAIN_ID", "WRONG_SIGNATURE", "BAD_ROUND_NUMBER", "INSUFFICIENT_BALANCE"],
      "description": "Description of the error."
    }
  },
  "required": ["status"]
}
```

Error types:

- MALFORMED_DATA: wrong input data, failed to deserialize, missing certain fields, etc.
- NOT_DEPOSITOR: the address is not an active depositor in the auction contract
- WRONG_CHAIN_ID: wrong chain id for the target chain
- WRONG_SIGNATURE: signature failed to verify
- BAD_ROUND_NUMBER: incorrect round, such as one from the past
- INSUFFICIENT_BALANCE: the bid amount specified in the request is higher than the deposit balance of the depositor in the contract

## Auctioneer Implementation

Rounds, to prevent the need for synchronization, are set to be at the each minute boundary based on unix time. 

#### Auction State

Add an `expressLaneAuctionState` struct to the sequencer with the following:

```go
type expressLaneAuctionState {
}
```

#### Processing Bids 

#### Delaying Non-Express Lane Txs

## OPTIONAL: Express Lane Client

Requirements:

- Commands for depositing and withdrawing from the express lane auction smart contract
- Simple CLI to check the balance of the express lane auction contract, number of other depositors, and one’s own balance + subtracted interest over time
- Checks for auction resolution events and sends fast lane txs automatically if the depositor is the winner of the auction. Notifies by logging that the user won the auction, with other optional notification methods
- If the user is not the express lane controller, txs will instead be sent over the regular RPC

## Questions

- *Given winners of rounds are announced offchain, as probabilities are computed by the sequencer, do we want to persist the history of round winners somewhere for posterity?*
- *How many txs per second are expected to be received over the input channel?*
