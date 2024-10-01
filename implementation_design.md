# Solidity Interface

The latest Solidity interface for the express lane auction contract can be found [here](https://github.com/OffchainLabs/nitro-contracts/pull/214/files). The latest Go implementation is [here](https://github.com/OffchainLabs/nitro/compare/express-lane-timeboost?expand=1)

# Offchain Components

## Auctioneer API

The auctioneer must expose a new RPC namespace called `auctioneer` and a RPC method called `timeboost_submitBid`

### `auctioneer_submitBid`

```json
{
  "type": "object",
  "properties": {
    "chainId": {
      "type": "bigInt",
      "description": "chain id of the target chain"
    },
    "expressLaneController": {
      "type": "address",
      "description": "hex string of the desired express lane controller address, 0x-prefixed"
    },
    "auctionContractAddress": {
      "type": "address",
      "description": "hex string of the auction contract address that the bid corresponds to, 0x-prefixed"
    },
    "round": {
      "type": "uint64",
      "description": "round number (0-indexed) for the round the bidder wants to become the controller of"
    },
    "amount": {
      "type": "bigInt",
      "description": "The amount in wei of the deposit ERC-20 token to bid"
    },
    "signature": {
      "type": "bytes",
      "description": "Ethereum signature over the bytes encoding of (keccak256(TIMEBOOST_BID), padTo32Bytes(chainId), auctionContractAddress, uint64ToBytes(round), padTo32Bytes(amount), expressLaneController), formatted according to EIP-191 or EIP-712 for clarity"
    }
  },
}
```

The auctioneer will perform the following validation:

- check the bid fields are not nil
- check if the auction contract address is correct
- check if the express lane controller address is defined
- check if the chain id is correct
- check if the bid is intended for the upcoming round
- check if the bidding was open at the time of receiving the bid
- check if the bid meets the minimum reserve price
- verify the signature and recover the sender address
- verify the sender is a depositor onchain and has enough balance

```json
{
  "type": "object",
  "properties": {
    "error": {
      "type": "string",
      "enum": ["MALFORMED_DATA", "NOT_DEPOSITOR", "WRONG_CHAIN_ID", "WRONG_SIGNATURE", "BAD_ROUND_NUMBER", "INSUFFICIENT_BALANCE", "RESERVE_PRICE_NOT_MET"],
      "description": "Description of the error."
    }
  },
}
```

Error types:

- MALFORMED_DATA: wrong input data, failed to deserialize, missing certain fields, etc.
- NOT_DEPOSITOR: the address is not an active depositor in the auction contract
- WRONG_CHAIN_ID: wrong chain id for the target chain
- WRONG_SIGNATURE: signature failed to verify
- BAD_ROUND_NUMBER: incorrect round, such as one from the past
- RESERVE_PRICE_NOT_MET: bid amount does not meet the minimum required reserve price onchain
- INSUFFICIENT_BALANCE: the bid amount specified in the request is higher than the deposit balance of the depositor in the contract

## Sequencer API

The sequencer must expose a new RPC namespace called `timeboost` and a RPC method called `timeboost_sendExpressLaneTransaction`

### `timeboost_sendExpressLaneTransaction`

```json
{
  "type": "object",
  "properties": {
    "chainId": {
      "type": "bigInt",
      "description": "chain id of the target chain"
    },
    "round": {
      "type": "uint64",
      "description": "round number (0-indexed) for the round the transaction is submitted for"
    },
    "auctionContractAddress": {
      "type": "address",
      "description": "hex string of the auction contract address that the bid corresponds to"
    },
    "sequenceNumber": {
      "type": "uint64",
      "description": "the per-round nonce of express lane submissions. Each submission to the express lane during a round increases this sequence number by one, and if submissions are received out of order, the sequencer will queue them for processing in order. This is reset to 0 at each round"
    },
    "transaction": {
      "type": "bytes",
      "description": "hex string of the RLP encoded transaction payload that submitter wishes to be sequenced through the express lane"
    },
    "options": {
      "type": "ArbitrumConditionalOptions",
      "description": "conditional options for Arbitrum transactions, supported by normal sequencer endpoint https://github.com/OffchainLabs/go-ethereum/blob/48de2030c7a6fa8689bc0a0212ebca2a0c73e3ad/arbitrum_types/txoptions.go#L71"
    },
    "signature": {
      "type": "bytes",
      "description": "Ethereum signature over the bytes encoding of (keccak256(TIMEBOOST_BID), padTo32Bytes(chainId), auctionContractAddress, uint64ToBytes(round), uint64ToBytes(sequenceNumber), transaction)"
    }
  },
}
```

The sequencer will perform the following validation:
- check the fields are not nil
- check if the chain id is correct
- check if the auction contract address is correct
- check the current round has an express lane controller
- check if the transaction is intended for the current round
- recover the signer's address
- verify the signer is the current express lane controller
- check the sequencer number of the transaction is in-order, otherwise queue for later. The sequence number is the per-round nonce for express lane submissions, starting at 0, maintained by the sequencer in-memory. If a sequence number is 0, and an express lane controller sends a message with number 3, it will get queued until it can get processed

Then, the sequencer will respond with:

```json
{
  "type": "object",
  "properties": {
    "error": {
      "type": "string",
      "enum": ["MALFORMED_DATA", "WRONG_CHAIN_ID", "WRONG_SIGNATURE", "BAD_ROUND_NUMBER", "NOT_EXPRESS_LANE_CONTROLLER", "NO_ONCHAIN_CONTROLLER"],
      "description": "Description of the error."
    }
  },
}
```

Error types:

- MALFORMED_DATA: wrong input data, failed to deserialize, missing certain fields, etc.
- WRONG_CHAIN_ID: wrong chain id for the target chain
- WRONG_SIGNATURE: signature failed to verify
- BAD_ROUND_NUMBER: incorrect round, such as one from the past
- NOT_EXPRESS_LANE_CONTROLLER: the sender is not the express lane controller
- NO_ONCHAIN_CONTROLLER: there is no defined, onchain express lane controller for the round