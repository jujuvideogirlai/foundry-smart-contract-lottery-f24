// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {console} from "forge-std/console.sol";

/**
 * @title A sample raffle contract
 * @author Júlia Polbach
 * @notice This contract is for creating a sample raffle.
 * @dev Implements Chainlink VRF for random number generation.
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /** Errors */
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpKeepNotNeeded(
        uint256 balance,
        uint256 players,
        uint256 state
    );

    /** Type Declarations */
    enum RaffleState {
        OPEN, // 0
        CALCULATING_WINNER // 1
    }

    /** State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    //@dev The duration of the raffle in seconds
    uint256 private immutable i_interval;
    uint256 private immutable i_entranceFee;
    bytes32 private immutable i_keyHash;
    uint32 private immutable i_callbackGasLimit;
    uint256 private i_subscriptionId;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address payable s_recentWinner;
    RaffleState private s_raffleState;

    /** Events */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    // When should the winner be picked?
    /**
     * @dev     This is the function that the Chainlink Network will call to see if the lottery is ready to pick a winner.
     *          The following should be true in order for upKeepNeeded to be true:
     *          1. The time interval has passed.
     *          2. The lottery is open.
     *          3. There contract has ETH (has players).
     *          4. Your subscription has enough LINK to pay the fee.
     * @param   - ignored.
     * @return  upKeepNeeded - true if the lottery is ready to pick a winner.
     * @return  - ignored.
     */
    function checkUpkeep(
        bytes memory /*checkData*/
    ) public view returns (bool upKeepNeeded, bytes memory /*performData*/) {
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        console.log("Block timestamp: %s", block.timestamp);
        console.log("Last time stamp: %s", s_lastTimeStamp);
        console.log("Interval: %s", i_interval);

        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        console.log("timePassed: %s", timePassed);
        upKeepNeeded = timePassed && isOpen && hasBalance && hasPlayers;
        return (upKeepNeeded, "");
    }

    function performUpkeep(bytes calldata /*performData*/) external {
        (bool upKeepNeeded, ) = checkUpkeep("");
        if (!upKeepNeeded) {
            revert Raffle__UpKeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING_WINNER;

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );

        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] calldata randomWords
    ) internal virtual override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;

        s_recentWinner = s_players[indexOfWinner];
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;

        emit WinnerPicked(s_recentWinner);

        (bool success, ) = s_recentWinner.call{value: address(this).balance}(
            ""
        );
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    //**  Getter functions */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getPlayers() external view returns (address payable[] memory) {
        return s_players;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
