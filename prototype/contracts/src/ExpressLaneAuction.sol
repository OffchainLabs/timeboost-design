// SPDX-License-Identifier: UNLICENSED
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
    address bidder;
    uint256 chainId;
    uint256 round;
    uint256 amount;
    bytes signature;
}

struct Withdrawal {
    uint256 amount;
    uint64 submittedRound;
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
    /// @param winningBidAmount        the amount in wei of the winning bid
    /// @param secondPlaceBidAmount    the amount in wei of the second-highest bid
    /// @param winningBidder           the address of the winner and designated express lane controller
    /// @param winnerRound             the round number for which the winner will be the express lane controller
    event AuctionResolved(
        uint256 winningBidAmount, 
        uint256 secondPlaceBidAmount,
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

    /// @notice Fetches the reserved address for the chain, used by the
    ///         DAO to upgrade configurations and resolve certain actions.
    /// @return the reserved address
    function chainOwnerAddress() external view returns (address);

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
    function finalizeWithdrawal() external;

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

import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract ExpressLaneAuction is IExpressLaneAuction {
    address chainOwnerAddr;
    address reservePriceSetterAddr;
    address bidReceiverAddr;
    uint64 roundDuration;
    uint256 initialTimestamp;
    uint256 currentReservePrice;
    uint256 minimalReservePrice;
    uint16 domainValue = 15;
    IERC20 stakeToken;

    error ZeroAmount();
    error IncorrectBidAmount();
    error InsufficientBalance();
    error NotExpressLaneController();
    error NotChainOwner();
    error NotReservePriceSetter();
    error LessThanMinReservePrice();
    error LessThanCurrentReservePrice();

    mapping(address => uint256) public depositBalance;
    mapping(address => Withdrawal) public pendingWithdrawalByBidder;
    mapping (uint256 => address) public expressLaneControllerByRound;
    
    constructor(
        address _chainOwnerAddr,
        address _reservePriceSetterAddr,
        address _bidReceiverAddr,
        uint64 _roundLengthSeconds,
        uint256 _initialTimestamp,
        address _stakeToken,
        uint256 _currentReservePrice,
        uint256 _minimalReservePrice
    ) {
        chainOwnerAddr = _chainOwnerAddr;
        reservePriceSetterAddr = _reservePriceSetterAddr;
        bidReceiverAddr = _bidReceiverAddr;
        roundDuration = _roundLengthSeconds;
        initialTimestamp = _initialTimestamp;
        currentReservePrice = _currentReservePrice;
        minimalReservePrice = _minimalReservePrice;
        stakeToken = IERC20(_stakeToken);
    }

    function chainOwnerAddress() external view returns (address) {
        return chainOwnerAddr;
    }
    
    function reservePriceSetterAddress() external view returns (address) {
        return reservePriceSetterAddr;
    }

    function bidReceiver() external view returns (address) {
        return bidReceiverAddr;
    }

    function currentExpressLaneController() external view returns (address) {
        return expressLaneControllerByRound[currentRound()];
    }

    function roundDurationSeconds() external view returns (uint64) {
        return roundDuration;
    }

    function initialRoundTimestamp() external view returns (uint256) {
        return initialTimestamp;
    }

    function bidderBalance(address bidder) external view returns (uint256) {
        return depositBalance[bidder];
    }

    function bidSignatureDomainValue() external view returns (uint16) {
        return domainValue;
    }
    
    function getCurrentReservePrice() external view returns (uint256) {
        return currentReservePrice;
    }
    
    function getminimalReservePrice() external view returns (uint256) {
        return minimalReservePrice;
    }

    function submitDeposit(uint256 amount) external {
        if (amount == 0) {
            revert ZeroAmount();
        }

        depositBalance[msg.sender] += amount;
        // TODO: Use safe transfer from.
        IERC20(stakeToken).transferFrom(msg.sender, address(this), amount);
        emit DepositSubmitted(msg.sender, amount);
    }

    function initiateWithdrawal(uint256 amount) external {
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (depositBalance[msg.sender] < amount) {
            revert InsufficientBalance();
        }
        Withdrawal memory existing = pendingWithdrawalByBidder[msg.sender];
        if (existing.amount > 0) {
            revert("withdrawal already initiated");
        }
        depositBalance[msg.sender] -= amount;
        pendingWithdrawalByBidder[msg.sender] = Withdrawal(amount, currentRound());
        emit WithdrawalInitiated(msg.sender, amount);
    }

    function finalizeWithdrawal() external {
        Withdrawal memory existing = pendingWithdrawalByBidder[msg.sender];
        if (existing.amount == 0) {
            revert("no withdrawal initiated");
        }
        uint64 current = currentRound();
        if (current != existing.submittedRound + 2) {
            revert("withdrawal is not finalized");
        }
        IERC20(stakeToken).transfer(msg.sender, existing.amount);
        emit WithdrawalFinalized(msg.sender, existing.amount);
    }

    function cancelUpcomingRound() external {
        uint64 upcomingRound = currentRound()+1;
        address controller = expressLaneControllerByRound[upcomingRound];
        if (msg.sender != controller) {
            revert NotExpressLaneController();
        }
        expressLaneControllerByRound[upcomingRound] = address(0);
    }

    function delegateExpressLane(address delegate) external {
        uint64 upcomingRound = currentRound()+1;
        address controller = expressLaneControllerByRound[upcomingRound];
        if (msg.sender != controller) {
            revert NotExpressLaneController();
        }
        expressLaneControllerByRound[upcomingRound] = delegate;
        emit ExpressLaneControlDelegated(msg.sender, delegate, upcomingRound);
    }

    function setReservePriceAddresses(address _reservePriceSetterAddr) external {
        if (msg.sender != chainOwnerAddr) {
            revert NotChainOwner();
        }
        reservePriceSetterAddr = _reservePriceSetterAddr;
    }

    function setMinimalReservePrice(uint256 _minimalReservePrice) external {
        if (msg.sender != chainOwnerAddr) {
            revert NotChainOwner();
        }
        minimalReservePrice = _minimalReservePrice;
    }
    
    function setCurrentReservePrice(uint256 _currentReservePrice) external {
        if (msg.sender != reservePriceSetterAddr) {
            revert NotReservePriceSetter();
        }
        if (_currentReservePrice < minimalReservePrice) {
            revert LessThanMinReservePrice();
        }
        currentReservePrice = _currentReservePrice;
    }

    function resolveAuction(Bid calldata bid1, Bid calldata bid2) external {
        if (bid1.chainId != bid2.chainId) {
            revert("chain ids do not match");
        }
        if (bid1.round != bid2.round) {
            revert("rounds do not match");
        }
        uint256 upcomingRound = currentRound() + 1;
        if (bid1.round != upcomingRound) {
            revert("not upcoming round");
        }
        // Ensure both bids are for depositors and are backed by sufficient funds.
        if (depositBalance[bid1.bidder] < bid1.amount) {
            revert IncorrectBidAmount();
        }
        if (depositBalance[bid2.bidder] < bid2.amount) {
            revert IncorrectBidAmount();
        }

        // Verify both bid signatures.
        if (!verifySignature(
            bid1.bidder,
            abi.encodePacked(domainValue, bid1.chainId, bid1.round, bid1.amount),
            bid1.signature
        )) {
            revert("invalid signature for first bid");
        }
        if (!verifySignature(
            bid2.bidder,
            abi.encodePacked(domainValue, bid2.chainId, bid2.round, bid2.amount),
            bid2.signature
        )) {
            revert("invalid signature for second bid");
        }

        // Deduct the second highest bid amount from the highest bidder's balance
        // and update the upcoming round express lane controller.
        if (bid1.amount > bid2.amount) {
            // TODO: Use safe transfer.
            depositBalance[bid1.bidder] -= bid2.amount;
            IERC20(stakeToken).transfer(bidReceiverAddr, bid2.amount);
            expressLaneControllerByRound[bid1.round] = bid1.bidder;
            emit AuctionResolved(
                bid1.amount, 
                bid2.amount,
                bid1.bidder,
                upcomingRound
            );
        } else {
            depositBalance[bid2.bidder] -= bid1.amount;
            IERC20(stakeToken).transfer(bidReceiverAddr, bid1.amount);
            expressLaneControllerByRound[bid2.round] = bid2.bidder;
            emit AuctionResolved(
                bid2.amount, 
                bid1.amount,
                bid2.bidder,
                upcomingRound
            );
        }
    }

    function resolveSingleBidAuction(Bid calldata bid) external {
        uint64 upcomingRound = currentRound()+1;
        if (bid.round != upcomingRound) {
            revert("not upcoming round");
        }
        if (depositBalance[bid.bidder] < bid.amount) {
            revert IncorrectBidAmount();
        }
        if (bid.amount < currentReservePrice) {
            revert LessThanCurrentReservePrice();
        }
        if (depositBalance[bid.bidder] < bid.amount) {
            revert IncorrectBidAmount();
        }
        if (!verifySignature(
            bid.bidder,
            abi.encodePacked(domainValue, bid.chainId, bid.round, bid.amount),
            bid.signature
        )) {
            revert("invalid signature for first bid");
        }
        depositBalance[bid.bidder] -= bid.amount;
        IERC20(stakeToken).transfer(bidReceiverAddr, bid.amount);
        expressLaneControllerByRound[bid.round] = bid.bidder;
        emit AuctionResolved(
            bid.amount,
            0,
            bid.bidder,
            upcomingRound
        );
    }

    function currentRound() public view returns (uint64) {
        if (initialTimestamp > block.timestamp) {
            return type(uint64).max;
        }
        return uint64((block.timestamp - initialTimestamp) / roundDuration);
    }

    function verifySignature(
        address signer,
        bytes memory message,
        bytes memory signature
    ) public pure returns (bool) {
        bytes32 messageHash = getMessageHash(message);
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        address recoveredSigner = recoverSigner(ethSignedMessageHash, signature);
        return recoveredSigner == signer;
    }

    // Function to hash the message
    function getMessageHash(bytes memory message) internal pure returns (bytes32) {
        return keccak256(message);
    }

    // Function to recreate the Ethereum signed message hash
    function getEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32) {
        /*
            Signature is produced from the Keccak256 hash of the concatenation of
            "\x19Ethereum Signed Message:\n" with the length of the message and the message itself.
            Here, "\x19" is the control character used to indicate that the string is a signed message.
            "\n" is a new line character.
        */
        return keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
    }

    // Function to recover the signer from the signature
    function recoverSigner(
        bytes32 _ethSignedMessageHash, bytes memory _signature
    ) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);
        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    // Helper function to split the signature into r, s and v
    function splitSignature(bytes memory sig)
        internal
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(sig.length == 65, "invalid signature length");

        assembly {
            // First 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // Second 32 bytes
            s := mload(add(sig, 64))
            // Final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        // If the signature is valid (and not malleable), v should be 27 or 28
        // However, as of EIP-155, v = 27 or 28 + chainId * 2 + 8
        if (v < 27) v += 27;
        return (r, s, v);
    }
}
