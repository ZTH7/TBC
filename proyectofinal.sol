// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IExecutableProposal {
    function executeProposal(
        uint256 proposalId,
        uint256 numVotes,
        uint256 numTokens
    ) external payable;
}

contract VotingToken is ERC20 {
    address owner;

    constructor(address owner_) ERC20("Voting Token", "VT") {
        owner = owner_;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "Can only execute by owner");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == owner, "Can only execute by owner");
        _burn(from, amount);
    }

    function getTotalSupply() public view returns (uint256) {
        require(msg.sender == owner, "Can only execute by owner");
        return totalSupply();
    }
}

contract QuadraticVoting {
    struct Proposal {
        address owner;
        string title;
        string description;
        uint256 budget;
        uint256 numVotes;
        address executableContract;
        mapping(address => uint256) votesRecord;
        address[] voters;
        bool approved;
        bool cancelled;
    }

    address owner;
    bool public votingOpen;
    uint256 public totalBudget;
    uint256 public numToken;
    uint256 public tokenPrice;

    uint256 public participantCounter;
    uint256 public proposalCounter;

    VotingToken public token;
    address[] public participants;
    uint256[] pendingProposals;
    uint256[] approvedProposals;
    mapping(uint256 => Proposal) public proposals;

    constructor(uint256 _tokenPrice, uint256 _numToken) {
        token = new VotingToken(address(this));
        tokenPrice = _tokenPrice;
        numToken = _numToken;
        owner = msg.sender;
        proposalCounter = 0;
        participantCounter = 0;
    }

    function openVoting(uint256 initialBudget) external {
        require(!votingOpen, "Voting already open");
        require(owner == msg.sender, "Only execute by contract owner");
        totalBudget = initialBudget;
        votingOpen = true;
    }

    function addParticipant() external payable {
        require(msg.value >= tokenPrice, "At least buy one token");
        for (uint256 i = 0; i < participants.length; i++) {
            require(
                participants[i] != msg.sender,
                "Participant already exists"
            );
        }
        uint256 tokensToMint = msg.value;
        token.mint(msg.sender, tokensToMint);

        participantCounter++;
    }

    function removeParticipant() external {
        bool isFound = false;
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i] == msg.sender) {
                participants[i] = participants[participants.length - 1];
                participants.pop();
                isFound = true;
            }
        }
        require(isFound, "Participant not found");
        payable(msg.sender).transfer(token.balanceOf(msg.sender) * tokenPrice);
        token.burn(msg.sender, token.balanceOf(msg.sender));
    }

    function addProposal(
        string memory title,
        string memory description,
        uint256 budget,
        address executableContract
    ) external {
        require(votingOpen, "Voting not open");
        Proposal storage p = proposals[proposalCounter];
        p.title = title;
        p.description = description;
        p.budget = budget;
        p.executableContract = executableContract;
        p.approved = false;
        p.cancelled = false;
        pendingProposals.push(proposalCounter++);
    }

    function cancelProposal(uint256 proposalId) external {
        require(votingOpen, "Voting not open");
        require(!proposals[proposalId].approved, "Proposal already approved");
        require(proposals[proposalId].owner == msg.sender, "");
        for (uint256 i = 0; i < pendingProposals.length; i++) {
            if (pendingProposals[i] == proposalId) {
                pendingProposals[i] = pendingProposals[
                    pendingProposals.length - 1
                ];
            }
        }
        pendingProposals.pop();

        Proposal storage p = proposals[proposalId];
        for (uint256 i = 0; i < p.voters.length; i++) {
            token.mint(p.voters[i], p.votesRecord[p.voters[i]]);
        }
    }

    function buyTokens() external payable {
        uint256 tokensToMint = msg.value / tokenPrice;
        require(
            token.getTotalSupply() + tokensToMint <= numToken,
            "There is no more token"
        );
        uint256 rest = msg.value % tokenPrice;
        token.mint(msg.sender, tokensToMint);
        if (rest > 0) payable(msg.sender).transfer(rest);
    }

    function sellTokens(uint256 amount) external {
        require(token.balanceOf(msg.sender) >= amount, "Not enough tokens");
        token.burn(msg.sender, amount);
        payable(msg.sender).transfer(amount * tokenPrice);
    }

    function getERC20() public view returns (address) {
        return address(token);
    }

    function getPendingProposals() public view returns (uint256[] memory) {
        return pendingProposals;
    }

    function getApprovedProposals() public view returns (uint256[] memory) {
        return approvedProposals;
    }

    function getSignalingProposals() public view returns (uint256[] memory) {
        uint256[] memory signalingProposals = new uint256[](
            pendingProposals.length
        );
        uint256 counter = 0;
        for (uint256 i = 0; i < pendingProposals.length; i++) {
            uint256 id = pendingProposals[i];
            if (proposals[id].budget == 0) {
                signalingProposals[counter++] = id;
            }
        }
        return signalingProposals;
    }

    function getProposalInfo(uint256 proposalId)
        public
        view
        returns (
            string memory title,
            string memory description,
            uint256 budget,
            address executableContract,
            uint256 numVotes,
            bool approved
        )
    {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.title,
            proposal.description,
            proposal.budget,
            proposal.executableContract,
            proposal.numVotes,
            proposal.approved
        );
    }

    function stake(uint256 proposalId, uint256 numVotes) external {
        require(votingOpen, "Voting not open");
        uint256 currentVotes = proposals[proposalId].votesRecord[msg.sender];
        if (currentVotes == 0) {
            proposals[proposalId].voters.push(msg.sender);
        }
        uint256 newVotes = currentVotes + numVotes;
        uint256 cost = newVotes * newVotes - currentVotes * currentVotes;

        require(token.balanceOf(msg.sender) >= cost, "Insufficient tokens");
        token.transferFrom(msg.sender, address(this), cost);
        proposals[proposalId].numVotes += numVotes;
        proposals[proposalId].votesRecord[msg.sender] = newVotes;
        if (proposals[proposalId].budget > 0) {
            totalBudget += cost * tokenPrice;
            _checkAndExecuteProposal(proposalId);
        }
    }

    function withdrawFromProposal(uint256 proposalId, uint256 numVotes)
        external
    {
        require(votingOpen, "Voting not open");
        require(
            !proposals[proposalId].approved,
            "This proposal has been approved."
        );
        uint256 currentVotes = proposals[proposalId].votesRecord[msg.sender];
        require(currentVotes >= numVotes, "");

        uint256 newVotes = currentVotes - numVotes;
        proposals[proposalId].numVotes -= numVotes;
        uint256 tokensToReturn = currentVotes *
            currentVotes -
            newVotes *
            newVotes;
        totalBudget -= tokensToReturn * tokenPrice;
        token.transferFrom(address(this), msg.sender, tokensToReturn);
    }

    function _checkAndExecuteProposal(uint256 proposalId) internal {
        Proposal storage proposal = proposals[proposalId];
        uint256 threshold = ((2 + (10 * proposal.budget) / totalBudget) *
            participants.length) /
            10 +
            pendingProposals.length;
        if (
            proposal.numVotes > threshold &&
            proposal.budget > 0 &&
            proposal.budget <= proposal.numVotes * tokenPrice
        ) {
            IExecutableProposal(proposal.executableContract).executeProposal{
                value: proposal.budget
            }(
                proposalId,
                proposal.numVotes,
                proposal.numVotes * proposal.numVotes
            );
            proposal.approved = true;
            for (uint256 i = 0; i < pendingProposals.length; i++) {
                if (pendingProposals[i] == proposalId) {
                    pendingProposals[i] = pendingProposals[
                        pendingProposals.length - 1
                    ];
                    approvedProposals.push(proposalId);
                }
            }
            totalBudget -= proposal.budget;
        }
    }

    function closeVoting() external {
        require(votingOpen, "Voting not open");
        votingOpen = false;
        // Return tokens for all non-approved proposals
        for (uint256 i = 0; i < pendingProposals.length; i++) {
            Proposal storage prop = proposals[pendingProposals[i]];
            if (prop.budget == 0) {
                IExecutableProposal(prop.executableContract).executeProposal{
                    value: 0
                }(
                    pendingProposals[i],
                    prop.numVotes,
                    prop.numVotes * prop.numVotes
                );
            }
            for (uint256 j = 0; j < prop.voters.length; j++) {
                token.transferFrom(
                    address(this),
                    prop.voters[j],
                    prop.votesRecord[prop.voters[j]]
                );
            }
        }
        payable(owner).transfer(totalBudget);
    }
}
