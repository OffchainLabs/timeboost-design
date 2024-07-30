### Terminology

The “target chain” is the chain for which we want to implement time boost.

“Governance” is the governance system for the target chain. For example, for Arbitrum One this would be the Arbitrum DAO.

The “deposit token” is an ERC-20 token on the target chain, designated by governance. This would likely be ARB for the Arbitrum One and Arbitrum Nova chains.

The "reserved address" is an address on the target chain which is used by the protocol. This address cannot be used for any other purpose, so it should be chosen in a way that will not collide with ordinary EOA or contract addresses.

### The auction

Control of the express lane in each round of the protocol is determined by a per-round auction, which is a sealed-bid, second-price auction. The auction is managed partly by an auction contract on the target chain, and partly by a party called the *autonomous auctioneer*, which is designated by governance, and will often be the same party who operates the sequencer.

The auction has a minimum reserve price, which is set by governance. The contract tracks the minimum reserve price, along with a current reserve price. The contract enforces that the current reserve price is never less than the minimum reserve price.

Governance can also designate an address as the reserve pricer. This address can call the auction contract to change the current reserve price to any value greater than or equal to the minimum reserve price. A parameter called `ReserveSubmissionSeconds` (default: 15) controls when this can be done: the contract will reject calls to change the current reserve price during a blackout period consisting of the `ReserveSubmissionSeconds` seconds before the bidding for a round closes. For a round that starts at time $t$, the blackout period is between $t-\mathrm{AuctionClosingSeconds}-\mathrm{ReserveSubmissionSeconds}$ inclusive and when the auction resolves or the round ends. (This ensures that bidders know the reserve price for at least `ReserveSubmissionSeconds` before they must submit their bids.)

Before bidding in an auction, a party must deposit funds into the auction contract. Deposits can be made, or funds added to an existing deposit, at any time.  A party can initiate a withdrawal of all of its deposited funds at any time, but a withdrawal request submitted during round `i` of the protocol will only be available to be claimed by the party at the beginning of round `i+2`; after this, the party can call the auction contract again to claim the funds and complete the withdrawal.

The auction for a round has a closing time that is `AuctionClosingSeconds` (default: 15) seconds before the beginning of the round.

Until the closing time, any party can send a bid to the autonomous auctioneer by RPC. The bid contains `(chainId, auctionContractAddress, roundNumber, bid, expressLaneControllerAddress, signature)` where `chainId` is the chain ID of the target chain, `auctionContractAddress` is the address of the auction contract that the winning bid will be submitted to, `roundNumber` is the round being bid for (current round + 1), `bid` is the value that the party is offering to pay, and `expressLaneControllerAddress` is the address to set as express lane controller in the event that the bid wins. `signature` is a signature by the bidder’s private key on the tuple `(chainId, auctionContractAddress, roundNumber, bid, expressLaneControllerAddress)`.

When the closing time is reached, the autonomous auctioneer will first discard any bid that is less than the current reserve price or greater than the bidder’s current funds deposited in the auction contract. Then:

*  if there are two or more remaining bids, the autonomous auctioneer will call the `resolveAuctionMultiBid` method of the auction contract, passing in the two highest bids. (If two bids have the same value, the tie is broken by hashing the bidder address concatenated with the respective byte-string representation of the bid using the Keccak256 hashing scheme, and treating the one with lexicographically larger hash as being the higher bid.) The auction contract will verify the signatures on these bids, and that they are signed by different addresses, that both are backed by funds deposited in the auction contract and that both meet the reserve. Then the auction contract will deduct the second-highest bid amount from the account of the highest bidder, and transfer those funds to a `beneficiary` account designated by governance, or burn them if governance specifies that the proceeds are to be burned. The `expressLaneControllerAddress` specified in the highest bid will become the express lane controller for the round.
* if there is one remaining bid, the autonomous auctioneer will call the `resolveAuctionSingleBid` method of the auction contract, passing in the one bid. The auction contract will verify the signature on this bid, that it is backed by funds deposited in the auction contract and that it meets the reserve. Then the auction contract will deduct the current reserve price from the account of the bidder, and transfer those funds to a `beneficiary` account designated by governance, or burn them if governance specifies that the proceeds are to be burned. The `expressLaneControllerAddress` of the bid will become the express lane controller for the round.
* if there are no remaining bids, the autonomous auctioneer will not call any methods on the auction contract, thus not setting a express lane controller for the round.

### Rounds in the protocol

The protocol proceeds in rounds. Each round lasts `RoundDurationSeconds` (default: 60) seconds, and the next round begins immediately when the current one ends. For simplicity and predictability, rounds should start and end on a timestamp (on the target chain) that is a multiple of `RoundDurationSeconds`.

For a round that will start its active phase at time `t`, the round proceeds like this:

- At any time between t-`AuctionClosingSeconds` and t, the autonomous auctioneer closes the auction by submitting a transaction to the auction contract, as described above. The autonomous auctioneer is trusted to follow the instructions specified above. This may designate a party as the express lane controller for the round, and if so it will deduct funds from that party's deposit account and distribute or burn those funds.

- At any time between the designation of the express lane controller for the round starting at t and the end of the round (t+`RoundDurationSeconds`), the express lane controller, or an alternative `transferrer` if set, can call the `transferExpressLaneController` on the auction contract to transfer the express lane controller right for the round to a new address. By calling `transferExpressLaneController` and transferring express lane controller rights the current controller loses all of its own rights in the round. The transferee receives express lane controller rights from the moment they are transferred, as well as the right to transfer to another address, either directly or by an alternative transferrer if set. Each express lane controller can set their own alternative `transferrer` by calling `setTransferrer` function at any time, this `transferrer` will have the ability to transfer the rights of any current or future round controlled by that express lane controller. Along with the new transferrer address, an optional round number is provided when calling `setTransferrer` which specifies when the transferrer can next be updated. If a round number is not provided the transferrer can be updated at any time.

  Such a transaction can be made multiple times during this time interval, as long as each one is sent by the then-current express lane controller.

- Between t and t+`RoundDurationSeconds` seconds, the express lane controller can submit fast lane transactions to the sequencer.  To submit a transaction T, construct a wrapper transaction with `to` address set to the reserved address, nonce set to a sequence number within this round, `maxPriorityFeePerGas` set to the round number, and  `data` containing T. This wrapper transaction should be signed by the express lane controller.

  On receiving a transaction to the reserved address, the sequencer verifies the express lane controller's signature on the transaction, verifies that `maxPriorityFeePerGas` equals the current round number, and verifies the sequence number (caching transactions with "future" sequence numbers, to be included after all previous sequence numbers within the round have been seen). If all of these verifications succeed, the sequencer extracts the inner "wrapped" transaction from the `data` field and sequences it immediately. (If verification fails, the sequencer discards the transaction.)

  Transactions arriving at the sequencer with `to` field not equal to the reserved address are artificially delayed by the sequencer for `NonExpressDelayMsec` (default: 200) milliseconds before being sequenced.

  This is a modified first come, first served sequencing policy, where the modification is the artificial delay on some transactions before sequencing.

- At t+`RoundLengthSeconds` seconds, the sequencer stops accepting express lane messages for the round. At this time, the round is completed.

  
