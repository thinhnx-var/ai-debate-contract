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
        uint8 chosenAgentId,
        uint256 amount,
        uint256 platformFeePercentage
    );

    event DebateResolved(
        uint256 indexed debateId,
        uint8 winnAgentId
    );

    event DebateUpdated(
        uint256 indexed debateId,
        uint8 winnAgentId
    );

    // define the data structures that we need
    // debateInfo
    struct Debate {
        bool isResolved;
        uint8 winAgentId;
        uint256 platformFeePercentage;
        uint256 endTimeStamp;
        uint8 agentAID;
        uint8 agentBID;
        uint256 totalAgentABetAmount;
        uint256 totalAgentBBetAmount;
    }
    // betInfo
    struct Bet {
        uint256 debateId;
        address bettor;
        uint256 amount;
        uint256 winAmount;
        uint8 chosenAgentId;
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
        uint8 _chosenAgent,
        uint256 _platformFeePercentage, // we need feeRatio to calculate the prize
        uint256 _endSessionTimeStamp
        ) external payable {

        require(_amount > 0, "Amount must be greater than 0");
        //TODO: need to check is debate is existed or not

        // insert debateInfo to debateList with _debateId as key. we get the existing debate if it is already existed, otherwise create a new debate
        Debate storage debate = debateList[_debateId];
        require(!debate.isResolved, "Debate session is already resolved");
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
            debate.platformFeePercentage = _platformFeePercentage;
            debate.endTimeStamp = _endSessionTimeStamp;
        }

        // record the betInfo of sender into the betList with _debateId // address // agentID as key
        Bet storage oldBet = betList[_debateId][msg.sender][_chosenAgent];
        if (oldBet.amount > 0) {
            oldBet.amount += _amount;
        } else {
            betList[_debateId][msg.sender][_chosenAgent] = Bet(_debateId, msg.sender, _amount, 0,  _chosenAgent, false);
        }
        // record the address of the bettor into the addressJoinedList with _debateId as key
        addressJoinedList[_debateId].push(msg.sender);
        emit BetPlaced(_debateId, msg.sender, _chosenAgent, _amount, _platformFeePercentage);
    }

    function transferNative(address payable _to, uint256 _amount) private {
        require(address(this).balance >= _amount, "Insufficient balance in contract"); 
        (bool success, ) = _to.call{value: _amount}(""); 
        require(success, "Transfer token failed");
    }


    // this function is used to resolve a debate by whitelist. It takes 2 parameters: _debateId, winAgentId. The reward is calculated base on _feeRatio of the debate.
    function resolveDebate(uint256 _debateId, uint8 _winAgentId) external {
        require(compareSenderWithAddressString("0xCa422Ade414CD9FC5a01e314A0c6cAe1080e6807"), "Only whitelist can resolve the debate");
        Debate storage debate = debateList[_debateId];
        require(!debate.isResolved, "Debate is already resolved");
        require(_winAgentId == debate.agentAID || _winAgentId == debate.agentBID, "Invalid agent");
        debate.isResolved = true;
        debate.winAgentId = _winAgentId;
        uint256 prizePool = debate.totalAgentABetAmount + debate.totalAgentBBetAmount;
        // we calculate the winAmount per bettor when debate is resolved
        for (uint256 i = 0; i < addressJoinedList[_debateId].length; i++) {
            address bettor = addressJoinedList[_debateId][i];
            Bet memory bet = betList[_debateId][bettor][_winAgentId];
            uint256 betProfit = bet.amount * ( 100 - debate.platformFeePercentage) / prizePool;
            if (bet.chosenAgentId != _winAgentId) {
                // do nothing, check next bettor
                break;
            } else {
                // winAmount = bet amount + profit
                uint256 winAmount = betProfit + bet.amount;
                bet.winAmount = winAmount;
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
        for (uint256 i = 0; i < addressJoinedList[_debateId].length; i++) {
            if (addressJoinedList[_debateId][i] == msg.sender) {
                break;
            }
            if (i == addressJoinedList[_debateId].length - 1) {
                revert("You did not joined in the battle");
            }
        }
        // check if the user has claimed the reward or not
        // find winAgentID
        uint256 winAgentID = debate.winAgentId;
        Bet storage bet = betList[_debateId][msg.sender][winAgentID];
        require(!bet.isClaimed, "You have already claimed the reward");

        require(bet.winAmount > 0, "You did not win the bet");

        // transfer the reward to the user
        address payable _recipient = convertAddressToPayable(msg.sender);
        transferNative(_recipient, bet.winAmount);

        bet.isClaimed = true;
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
    mapping(address => bool) public whitelist;
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