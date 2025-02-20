// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/*
    In this sample code, we are going to create a smart contract for AI Debate. The smart contract will have the following features:
    - Place a bet on a debate
    - Resolve a debate
    - Claim the reward
    - Get the debate related informations
    We are not creating proxy contract in this sample code.
    We are using Ownable contract from OpenZeppelin to manage the ownership of the contract.
    We are not checking for endSessionTimeStamp in placeBet function. We will add it later when we have the function to create / update the debate session.
 */

contract AIDebate is Initializable, Ownable {
    constructor(address initialOwner) Ownable(initialOwner) {}
    // define the events that we need
    event BetPlaced(
        uint256 indexed debateId,
        address indexed bettor,
        uint chosenAgentId,
        uint256 amount,
        uint256 platformFeePercentage
    );

    event DebateCreated(
        uint256 indexed debateId,
        uint agentAID,
        uint agentBID,
        uint256 platformFeePercentage,
        uint256 publicTimeStamp,
        uint256 startTimeStamp,
        uint256 sessionDuration
    );

    event DebateDeleted(
        uint256 indexed debateId
    );

    event DebateResolved(
        uint256 indexed debateId,
        uint winnAgentId
    );
    event DebateUpdated(
        uint256 indexed debateId,
        uint agentAID,
        uint agentBID,
        uint256 platformFeePercentage,
        uint256 publicTimeStamp,
        uint256 startTimeStamp,
        uint256 sessionDuration
    );

    event UserClaimed(
        uint256 indexed debateId,
        address indexed bettor,
        uint chosenAgentId,
        uint256 amount
    );

    //default platform fee
    uint256 public defaultPlatformFeePercentage = 5;
    uint256 private fiveMinsDuration = 5*60; // 5 mins in seconds
    uint256 private thirtyMinsBeforePublish = 30*60; // 30 mins in seconds

    // define the data structures that we need
    // debateInfo
    struct Debate {
        bool isResolved;
        uint winAgentId;
        uint256 platformFeePercentage;
        uint256 sessionDuration; // before endTime - 5m, bettors can place bet, afterthat, no one can place bet
        uint256 startTimeStamp;
        uint256 publicTimeStamp;
        uint agentAID;
        uint agentBID;
        uint256 totalAgentABetAmount;
        uint256 totalAgentBBetAmount;
    }
    // betInfo
    struct Bet {
        uint256 debateId;
        address bettor;
        uint256 amount;
        uint256 winAmount;
        uint chosenAgentId;
        bool isClaimed;
    }

    // create instance of mapping for debates and bets.
    mapping(uint256 => Debate) public debateList; // store debateID to debate info. this list will be filled by admin ?
    mapping(uint256 => mapping (address => mapping (uint256 => Bet))) public betList; // store debateID to bettor to bet info for each debate
    mapping(uint256 => address[]) public addressJoinedList; // store list of bettors to each debateID for faster retrieval?? IDK

    // this placeBet function is used to place a bet on a debate. It takes 4 parameters: _debateId, _amount, _chosenAgent, _feeRatio. For now, this placeBet also create a debate
    function placeBet(
        uint256 _debateId,
        uint256 _amount,
        uint _chosenAgent
        ) external payable {

        require(_amount > 0, "Amount must be greater than 0");
        //TODO: need to check is debate is existed or not

        // insert debateInfo to debateList with _debateId as key. we get the existing debate if it is already existed, otherwise create a new debate
        Debate storage debate = debateList[_debateId];
        require(debate.publicTimeStamp > 0, "Debate is not published yet");
        require(debate.startTimeStamp != 0, "Debate is deleted");
        require(!debate.isResolved, "Debate session is already resolved");
        require(block.timestamp > debate.publicTimeStamp, "Debate session is not started yet");
        require(block.timestamp < debate.startTimeStamp + debate.sessionDuration - fiveMinsDuration, "Can not place bet anymore");
        // value sent must be greater than or equal to the amount
        require(msg.value >= _amount, "Fee amount is not correct");

        // if there is no debate, create a new debate. Otherwise, update the existing debate
        if (_chosenAgent == debate.agentAID) {
            debate.totalAgentABetAmount += _amount;
        } else if (_chosenAgent == debate.agentBID) {
            debate.totalAgentBBetAmount += _amount;
        } else {
            require(debate.agentAID == 0 || debate.agentBID == 0, "Both agents are already assigned");
            if (debate.agentAID == 0) {
            debate.agentAID = _chosenAgent;
            debate.totalAgentABetAmount += _amount;
            } else {
            debate.agentBID = _chosenAgent;
            debate.totalAgentBBetAmount += _amount;
            }
        }

        // record the betInfo of sender into the betList with _debateId // address // agentID as key
        Bet storage oldBet = betList[_debateId][msg.sender][_chosenAgent];
        if (oldBet.amount > 0) {
            oldBet.amount += _amount;
        } else {
            // Bet: debateId, bettor, amount, winAmount, chosenAgentId, isClaimed
            betList[_debateId][msg.sender][_chosenAgent] = Bet(_debateId, msg.sender, _amount, 0,  _chosenAgent, false);
        }
        // record the address of the bettor into the addressJoinedList with _debateId as key
        addressJoinedList[_debateId].push(msg.sender);
        emit BetPlaced(_debateId, msg.sender, _chosenAgent, _amount, debate.platformFeePercentage);
    }

    // admin create debate
    function adminCreateDebate(uint256 _debateId, uint _agentAID, uint _agentBID, uint256 _platformFeePercentage, uint256 _publicTimeStamp, uint256 _startTimeStamp, uint256 _sessionDuration) external onlyOwner {
        Debate storage debate = debateList[_debateId];
        require(debate.agentAID == 0 && debate.agentBID == 0, "Debate is already created");
        require(_startTimeStamp + _sessionDuration > _publicTimeStamp, "End time must be greater than public time");
        debate.agentAID = _agentAID;
        debate.agentBID = _agentBID;
        if (_platformFeePercentage == 0) {
            debate.platformFeePercentage = defaultPlatformFeePercentage;
        } else {
            debate.platformFeePercentage = _platformFeePercentage;
        }
        debate.publicTimeStamp = _publicTimeStamp;
        debate.startTimeStamp = _startTimeStamp;
        debate.sessionDuration = _sessionDuration;
        emit DebateCreated(_debateId, _agentAID, _agentBID, _platformFeePercentage, _publicTimeStamp, _startTimeStamp, _sessionDuration);
    }

    // admin update debate
    function adminUpdateDebate(uint256 _debateId, uint _agentAID, uint _agentBID, uint256 _platformFeePercentage, uint256 _publicTimeStamp, uint256 _startTimeStamp, uint256 _sessionDuration) external onlyOwner {
        Debate storage debate = debateList[_debateId];
        require(debate.agentAID != 0 && debate.agentBID != 0, "Debate is not created yet");
        require(block.timestamp < debate.publicTimeStamp - thirtyMinsBeforePublish, "Can not modify debate anymore");
        debate.agentAID = _agentAID;
        debate.agentBID = _agentBID;
        if (_platformFeePercentage == 0) {
            debate.platformFeePercentage = defaultPlatformFeePercentage;
        } else {
            debate.platformFeePercentage = _platformFeePercentage;
        }
        debate.publicTimeStamp = _publicTimeStamp;
        debate.startTimeStamp = _startTimeStamp;
        debate.sessionDuration = _sessionDuration;
        emit DebateUpdated(_debateId, _agentAID, _agentBID, _platformFeePercentage, _publicTimeStamp, _startTimeStamp, _sessionDuration);
    }

    // admin delete debate - admin will set time to 0
    function adminDeleteDebate(uint256 _debateId) external onlyOwner {
        Debate storage debate = debateList[_debateId];
        require(block.timestamp < debate.publicTimeStamp - thirtyMinsBeforePublish, "Can not remove debate anymore");
        require(debate.agentAID != 0 && debate.agentBID != 0, "Debate is not created yet");
        debate.publicTimeStamp = 0;
        debate.startTimeStamp = 0;
        debate.sessionDuration = 0;
        // consider event
        emit DebateDeleted(_debateId);
    }
    // function transferCoin(address payable _to, uint256 _amount) private  {
    //     require(address(this).balance >= _amount, "Insufficient balance in contract"); 
    //     (bool success, ) = _to.call{value: _amount}(""); 
    //     require(success, "Transfer token failed");
    // }


    // this function is used to resolve a debate by whitelist. It takes 2 parameters: _debateId, winAgentId. The reward is calculated base on _feeRatio of the debate.
    function adminResolveDebate(uint256 _debateId, uint _winAgentId) external onlyOwner {
        Debate storage debate = debateList[_debateId];
        require(!debate.isResolved, "Debate is already resolved");
        require(_winAgentId == debate.agentAID || _winAgentId == debate.agentBID, "Invalid agent");
        debate.isResolved = true;
        debate.winAgentId = _winAgentId;
        uint256 prizePool = debate.totalAgentABetAmount + debate.totalAgentBBetAmount;
        // we calculate the winAmount per bettor when debate is resolved
        for (uint256 i = 0; i < addressJoinedList[_debateId].length; i++) {
            address bettor = addressJoinedList[_debateId][i];
            Bet storage bet = betList[_debateId][bettor][_winAgentId];
            if (bet.chosenAgentId == _winAgentId) {
                uint256 betProfit = 0;
                if (bet.chosenAgentId == debate.agentAID) {
                    betProfit = (bet.amount / debate.totalAgentABetAmount) * prizePool * (100 - debate.platformFeePercentage) / 100;
                }
                if ( bet.chosenAgentId == debate.agentBID) {
                    betProfit = (bet.amount / debate.totalAgentBBetAmount) * prizePool * (100 - debate.platformFeePercentage) / 100;
                }
                bet.winAmount = betProfit;
            }
        }

        emit DebateResolved(_debateId, _winAgentId);
    }

    // userClaim let user claim the reward after the debate is resolved. It takes 1 parameter: _debateId. It checks if the user is bettor or not, if the user has claimed the reward or not, and transfer the reward to the user.
    function userClaim(uint256 _debateId) external {
        // check if the debate is resolved or not
        Debate storage debate = debateList[_debateId];
        require(debate.isResolved, "Debate is not resolved yet");
        
        // check if the user is bettor or not
        bool isBettor = false;
        for (uint256 i = 0; i < addressJoinedList[_debateId].length; i++) {
            if (addressJoinedList[_debateId][i] == msg.sender) {
                isBettor = true;
            }
        }
        require(isBettor, "You did not place any bet on this debate");
        // check if the user has claimed the reward or not
        // find winAgentID
        uint256 winAgentID = debate.winAgentId;
        Bet storage bet = betList[_debateId][msg.sender][winAgentID];
        require(!bet.isClaimed, "You have already claimed the reward");

        require(bet.winAmount > 0, "You did not win the bet");

        // transfer the reward to the user
        address payable _recipient = convertAddressToPayable(msg.sender);
        require(address(this).balance >= bet.winAmount, "Insufficient balance in contract");
        _recipient.transfer(bet.winAmount); // Automatically reverts on failure
        bet.isClaimed = true;

        emit UserClaimed(_debateId, msg.sender, bet.chosenAgentId, bet.winAmount);
    }

    // for now we dont have adminSetDebateSession function. So these functions are enough.

    // this function is used to convert address to payable address - helper function
    function convertAddressToPayable(address _address) private pure returns (address payable) {
        return payable(_address); 
    }

    function getDebateInfo(uint256 _debateId) external view returns (Debate memory) {
        Debate storage debate = debateList[_debateId];
        return debate;
    }


    // For whitelist // 1 of 3 ways to do whitelist: 1. Use a mapping. 2. Use severside verification. 3. Use a contract and merkle tree
    mapping(address => bool) private whitelist;
    function addWhitelist(address _address) external onlyOwner {
        whitelist[_address] = true;
    }
    function removeWhitelist(address _address) external onlyOwner {
        whitelist[_address] = false;
    }

    // compare address and sender - helper
    function compareSenderWithAddressString(string memory _addressString) private view returns (bool) {
        bytes memory senderBytes = abi.encodePacked(msg.sender);
        bytes memory addressStringBytes = bytes(_addressString);

        // Check if both are of the same length (20 bytes for addresses)
        if (senderBytes.length != 20 || addressStringBytes.length != 20) {
            return false;
        }

        for (uint256 i = 0; i < 20; i++) {
            if (senderBytes[i] != addressStringBytes[i]) {
                return false;
            }
        }

        return true;
    }

}