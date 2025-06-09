// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
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
    We are not using math lib just for checking playformFeePercentage calculation. We just mannually calculate it.
 */

contract AIDebate is Initializable, Ownable {
    constructor(address initialOwner, address initialDeployer) Ownable(initialOwner) {
        modList.push(initialOwner);
        modList.push(initialDeployer);
    }
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
    //platformFeePercentage maximum is 10000. 1 represents 0.01%
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

    event DebateMarkedRefundable(
        uint256 indexed debateId
    );

    event UserRefunded(
        uint256 indexed debateId,
        address indexed bettor,
        uint256 amount
    );
    event refundSuccessful(
        uint256 indexed debateId,
        uint256 amountOfUsers
    );

    //default platform fee
    uint256 public defaultPlatformFeePercentage = 5;
    uint256 private fiveMinsDuration = 5*60; // 5 mins in seconds
    uint256 private thirtyMinsBeforePublish = 30*60; // 30 mins in seconds

    // define the data structures that we need
    // debateInfo
    struct Debate {
        bool isResolved;
        bool isRefundable;
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
        bool isRefunded;
    }
    
    // refund info for a user
    struct UserRefundInfo {
        address user;
        uint256 amountOfRefund;
        bool refunded;
    }
    
    address[] public modList;

    modifier onlyMod() {
        bool isAllowed = false;
        for (uint256 i = 0; i < modList.length; i++) {
            if (modList[i] == msg.sender) {
                isAllowed = true;
                break;
            }
        }
        require(isAllowed, "Not allowed");
        _;
    }

    function addMod(address _mod) external onlyOwner {
        modList.push(_mod);
    }

    function removeMod(address _mod) external onlyOwner {
        for (uint256 i = 0; i < modList.length; i++) {
            if (modList[i] == _mod) {
                modList[i] = modList[modList.length - 1]; // Move last mod to the removed spot
                modList.pop(); // Remove last element
                break;
            }
        }
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
        require(!debate.isRefundable, "Debate is marked as refundable, no new bets allowed");
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
            // Bet: debateId, bettor, amount, winAmount, chosenAgentId, isClaimed, isRefunded
            betList[_debateId][msg.sender][_chosenAgent] = Bet(_debateId, msg.sender, _amount, 0,  _chosenAgent, false, false);
        }
        // record the address of the bettor into the addressJoinedList with _debateId as key
        // Check if the address is already in the list
        bool alreadyJoined = false;
        for (uint256 i = 0; i < addressJoinedList[_debateId].length; i++) {
            if (addressJoinedList[_debateId][i] == msg.sender) {
                alreadyJoined = true;
                break;
            }
        }

        // If the address is not in the list, add it
        if (!alreadyJoined) {
            addressJoinedList[_debateId].push(msg.sender);
        }
        
        emit BetPlaced(_debateId, msg.sender, _chosenAgent, _amount, debate.platformFeePercentage);
    }

    // admin create debate
    function adminCreateDebate(uint256 _debateId, uint _agentAID, uint _agentBID, uint256 _platformFeePercentage, uint256 _publicTimeStamp, uint256 _startTimeStamp, uint256 _sessionDuration) external onlyMod {
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
    function adminUpdateDebate(uint256 _debateId, uint _agentAID, uint _agentBID, uint256 _platformFeePercentage, uint256 _publicTimeStamp, uint256 _startTimeStamp, uint256 _sessionDuration) external onlyMod {
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
    function adminDeleteDebate(uint256 _debateId) external onlyMod {
        Debate storage debate = debateList[_debateId];
        require(block.timestamp < debate.publicTimeStamp - thirtyMinsBeforePublish, "Can not remove debate anymore");
        require(debate.agentAID != 0 && debate.agentBID != 0, "Debate is not created yet");
        debate.publicTimeStamp = 0;
        debate.startTimeStamp = 0;
        debate.sessionDuration = 0;
        // consider event
        emit DebateDeleted(_debateId);
    }

    // admin mark debate as refundable - this allows users to get refunds instead of resolving the debate
    function adminMarkDebateRefundable(uint256 _debateId) external onlyMod {
        Debate storage debate = debateList[_debateId];
        require(debate.agentAID != 0 && debate.agentBID != 0, "Debate is not created yet");
        require(!debate.isResolved, "Debate is already resolved");
        require(!debate.isRefundable, "Debate is already marked as refundable");
        
        debate.isRefundable = true;
        
        emit DebateMarkedRefundable(_debateId);
    }

    // admin process refunds for all users who bet on a refundable debate
    function adminProcessRefunds(uint256 _debateId) external onlyMod {
        Debate storage debate = debateList[_debateId];
        require(debate.isRefundable, "Debate is not marked as refundable");
        require(!debate.isResolved, "Cannot refund resolved debate");
        
        // Refund all bettors for both agents
        for (uint256 i = 0; i < addressJoinedList[_debateId].length; i++) {
            address bettor = addressJoinedList[_debateId][i];
            
            // Check bet for agent A
            Bet storage betA = betList[_debateId][bettor][debate.agentAID];
            if (betA.amount > 0 && !betA.isRefunded && !betA.isClaimed) {
                _processRefund(_debateId, bettor, debate.agentAID, betA);
            }
            
            // Check bet for agent B
            Bet storage betB = betList[_debateId][bettor][debate.agentBID];
            if (betB.amount > 0 && !betB.isRefunded && !betB.isClaimed) {
                _processRefund(_debateId, bettor, debate.agentBID, betB);
            }
        }
        emit refundSuccessful(
            _debateId,
            addressJoinedList[_debateId].length
        );
    }

    // internal function to process individual refund
    function _processRefund(uint256 _debateId, address bettor, uint /* agentId */, Bet storage bet) internal {
        require(bet.amount > 0, "No bet amount to refund");
        require(!bet.isRefunded, "Already refunded");
        require(!bet.isClaimed, "Cannot refund claimed bet");
        
        uint256 refundAmount = bet.amount;
        bet.isRefunded = true;
        
        address payable recipient = payable(bettor);
        require(address(this).balance >= refundAmount, "Insufficient contract balance");
        
        recipient.transfer(refundAmount);
        
        emit UserRefunded(_debateId, bettor, refundAmount);
    }

    // this function is used to resolve a debate by whitelist. It takes 2 parameters: _debateId, winAgentId. The reward is calculated base on _feeRatio of the debate.
    function adminResolveDebate(uint256 _debateId, uint _winAgentId) external onlyMod {
        Debate storage debate = debateList[_debateId];
        require(!debate.isResolved, "Debate is already resolved");
        require(_winAgentId == debate.agentAID || _winAgentId == debate.agentBID, "Invalid agent");
        debate.isResolved = true;
        debate.winAgentId = _winAgentId;
        uint256 prizePool = debate.totalAgentABetAmount + debate.totalAgentBBetAmount;
        uint256 profitPercentage = 10000 - debate.platformFeePercentage;

        // We calculate the winAmount per bettor when debate is resolved
        for (uint256 i = 0; i < addressJoinedList[_debateId].length; i++) {
            address bettor = addressJoinedList[_debateId][i];
            Bet storage betRecord = betList[_debateId][bettor][_winAgentId];
            if (betRecord.chosenAgentId == _winAgentId) {
            uint256 betProfit = 0;
            // need to check if totalAgentABetAmount or totalAgentBBetAmount is 0 or not
            if (betRecord.chosenAgentId == debate.agentAID && debate.totalAgentABetAmount == 0) {
                betProfit = betRecord.amount * profitPercentage / 10000;
            } else if (betRecord.chosenAgentId == debate.agentBID && debate.totalAgentBBetAmount == 0) {
                betProfit = betRecord.amount * profitPercentage / 10000;
            }
            if (betRecord.chosenAgentId == debate.agentAID && debate.totalAgentABetAmount > 0) {
                betProfit = (betRecord.amount * prizePool * profitPercentage) / (debate.totalAgentABetAmount * 10000);
            } else if (betRecord.chosenAgentId == debate.agentBID && debate.totalAgentBBetAmount > 0) {
                betProfit = (betRecord.amount * prizePool * profitPercentage) / (debate.totalAgentBBetAmount * 10000);
            }
            betRecord.winAmount = betProfit;
            }
        }

        emit DebateResolved(_debateId, _winAgentId);
    }

    // userClaim let user claim the reward after the debate is resolved. It takes 1 parameter: _debateId. It checks if the user is bettor or not, if the user has claimed the reward or not, and transfer the reward to the user.
    function userClaim(uint256 _debateId) external {
        // check if the debate is resolved or not
        Debate storage debate = debateList[_debateId];
        require(debate.isResolved, "Debate is not resolved yet");
        require(!debate.isRefundable, "Debate is refundable, use refund instead of claim");
        
        // check if the user is bettor or not
        bool isBettor = false;
        for (uint256 i = 0; i < addressJoinedList[_debateId].length; i++) {
            if (addressJoinedList[_debateId][i] == msg.sender) {
                isBettor = true;
                break; // Exit the loop early if the bettor is found
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

    // userRefund allows users to claim refunds for debates marked as refundable
    function userRefund(uint256 _debateId) external {
        Debate storage debate = debateList[_debateId];
        require(debate.isRefundable, "Debate is not marked as refundable");
        require(!debate.isResolved, "Cannot refund resolved debate");
        
        // check if the user is bettor or not
        bool isBettor = false;
        for (uint256 i = 0; i < addressJoinedList[_debateId].length; i++) {
            if (addressJoinedList[_debateId][i] == msg.sender) {
                isBettor = true;
                break;
            }
        }
        require(isBettor, "You did not place any bet on this debate");
        
        bool refundProcessed = false;
        
        // Process refund for agent A bet if exists
        Bet storage betA = betList[_debateId][msg.sender][debate.agentAID];
        if (betA.amount > 0 && !betA.isRefunded && !betA.isClaimed) {
            uint256 refundAmount = betA.amount;
            betA.isRefunded = true;
            refundProcessed = true;
            
            address payable recipient = payable(msg.sender);
            require(address(this).balance >= refundAmount, "Insufficient contract balance");
            recipient.transfer(refundAmount);
            
            emit UserRefunded(_debateId, msg.sender, refundAmount);
        }
        
        // Process refund for agent B bet if exists
        Bet storage betB = betList[_debateId][msg.sender][debate.agentBID];
        if (betB.amount > 0 && !betB.isRefunded && !betB.isClaimed) {
            uint256 refundAmount = betB.amount;
            betB.isRefunded = true;
            refundProcessed = true;
            
            address payable recipient = payable(msg.sender);
            require(address(this).balance >= refundAmount, "Insufficient contract balance");
            recipient.transfer(refundAmount);
            
            emit UserRefunded(_debateId, msg.sender, refundAmount);
        }
        
        // Ensure at least one refund was processed in this transaction
        require(refundProcessed, "No eligible bets found for refund");
    }

    // for now we dont have adminSetDebateSession function. So these functions are enough.

    // convert address to payable address - helper function
    function convertAddressToPayable(address _address) private pure returns (address payable) {
        return payable(_address); 
    }
    // get debate informations
    function getDebateInfo(uint256 _debateId) external view returns (Debate memory) {
        Debate storage debate = debateList[_debateId];
        return debate;
    }

    // check if a debate is refundable
    function isDebateRefundable(uint256 _debateId) external view returns (bool) {
        return debateList[_debateId].isRefundable;
    }

    // get refund status for a specific bet
    function getUserRefundStatus(uint256 _debateId, address _user, uint _agentId) external view returns (bool isRefunded, uint256 amount) {
        Bet storage bet = betList[_debateId][_user][_agentId];
        return (bet.isRefunded, bet.amount);
    }

    // get refundable amount for a specific user in a debate
    function getUserRefundableAmount(uint256 _debateId, address _user) external view returns (uint256) {
        Debate storage debate = debateList[_debateId];
        
        // Return 0 if debate is not refundable or already resolved
        if (!debate.isRefundable || debate.isResolved) {
            return 0;
        }
        
        uint256 totalRefundable = 0;
        
        // Check agent A bet
        Bet storage betA = betList[_debateId][_user][debate.agentAID];
        if (betA.amount > 0 && !betA.isRefunded && !betA.isClaimed) {
            totalRefundable += betA.amount;
        }
        
        // Check agent B bet
        Bet storage betB = betList[_debateId][_user][debate.agentBID];
        if (betB.amount > 0 && !betB.isRefunded && !betB.isClaimed) {
            totalRefundable += betB.amount;
        }
        
        return totalRefundable;
    }

    // owner can withdraw all the balance in the contract (both for unresolved and resolved debates)
    function withdrawAll() external onlyOwner {
        address payable _recipient = convertAddressToPayable(msg.sender);
        _recipient.transfer(address(this).balance);
    }
    // withdraw by debateID - for resolved debates only
    function withdrawByID(uint256 _debateId) external onlyOwner {
        Debate storage debate = debateList[_debateId];
        require(debate.isResolved, "Debate is not resolved yet");
        require(debate.winAgentId != 0, "Debate is not resolved yet");
        uint256 prizePool = debate.totalAgentABetAmount + debate.totalAgentBBetAmount;
        uint256 amountToWithdraw = (prizePool * debate.platformFeePercentage) / 10000;
        address payable _recipient = convertAddressToPayable(msg.sender);
        require(address(this).balance >= amountToWithdraw, "Insufficient balance in contract");
        _recipient.transfer(amountToWithdraw);
    }

    function withdrawByAmount(uint256 _amount) external onlyOwner {
        address payable _recipient = convertAddressToPayable(msg.sender);
        require(address(this).balance >= _amount, "Insufficient balance in contract");
        _recipient.transfer(_amount);
    }

    // get all users' refund information for a debate
    function getUsersRefundInfo(uint256 _debateId) external view returns (UserRefundInfo[] memory) {
        Debate storage debate = debateList[_debateId];
        address[] memory debateUsers = addressJoinedList[_debateId];
        uint256 userCount = debateUsers.length;
        
        // Initialize return array
        UserRefundInfo[] memory usersRefundInfo = new UserRefundInfo[](userCount);
        
        // Populate array with user refund information
        for (uint256 i = 0; i < userCount; i++) {
            address user = debateUsers[i];
            
            // Calculate total bet amount for this user
            uint256 totalBetAmount = 0;
            bool hasRefunded = false;
            
            // Check agent A bet
            Bet storage betA = betList[_debateId][user][debate.agentAID];
            if (betA.amount > 0) {
                totalBetAmount += betA.amount;
                if (betA.isRefunded) {
                    hasRefunded = true;
                }
            }
            
            // Check agent B bet
            Bet storage betB = betList[_debateId][user][debate.agentBID];
            if (betB.amount > 0) {
                totalBetAmount += betB.amount;
                if (betB.isRefunded) {
                    hasRefunded = true;
                }
            }
            
            // For refunded status, check if ALL user's bets are refunded
            // (a user is considered fully refunded only if all their bets are refunded)
            bool fullyRefunded = false;
            if (totalBetAmount > 0) {
                bool allBetsRefunded = true;
                
                // Check if agent A bet exists and is refunded (or doesn't exist)
                if (betA.amount > 0 && !betA.isRefunded) {
                    allBetsRefunded = false;
                }
                
                // Check if agent B bet exists and is refunded (or doesn't exist)  
                if (betB.amount > 0 && !betB.isRefunded) {
                    allBetsRefunded = false;
                }
                
                fullyRefunded = allBetsRefunded;
            }
            
            usersRefundInfo[i] = UserRefundInfo({
                user: user,
                amountOfRefund: totalBetAmount,
                refunded: fullyRefunded
            });
        }
        
        return usersRefundInfo;
    }

    // // compare address and sender - helper
    // function compareSenderWithAddressString(string memory _addressString) private view returns (bool) {
    //     bytes memory senderBytes = abi.encodePacked(msg.sender);
    //     bytes memory addressStringBytes = bytes(_addressString);

    //     // Check if both are of the same length (20 bytes for addresses)
    //     if (senderBytes.length != 20 || addressStringBytes.length != 20) {
    //         return false;
    //     }

    //     for (uint256 i = 0; i < 20; i++) {
    //         if (senderBytes[i] != addressStringBytes[i]) {
    //             return false;
    //         }
    //     }

    //     return true;
    // }
}