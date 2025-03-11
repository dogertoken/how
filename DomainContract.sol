// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract LotDomain {
    struct Domain {
        string name;
        address owner;
        uint256 expiry;
        bool forAuction;
        uint256 minBid;
        bool isRented;
        address renter;
        uint256 rentPaid;
        uint256 rentTarget;
        uint256 reputation;
        string ipfsHash; // Untuk hosting website di IPFS
    }

    uint256 public constant DURATION = 365 days;

    uint256 public nextId = 1;
    mapping(uint256 => Domain) public domains;
    mapping(string => uint256) private nameToId;
    mapping(string => address) public nameToAddress;
    mapping(string => mapping(string => address)) public subdomains;
    mapping(uint256 => uint256) public domainStake;
    mapping(uint256 => address) public auctionHighestBidder;
    mapping(uint256 => uint256) public auctionHighestBid;
    mapping(address => address[]) public guardians;
    mapping(string => address[]) public domainTrustees;

    event DomainRegistered(string name, address owner, uint256 expiry);
    event DomainRenewed(string name, uint256 newExpiry);
    event DomainTransferred(string name, address from, address to);
    event DomainStaked(uint256 domainId, address staker, uint256 amount);
    event DomainAuctionStarted(string name, uint256 minBid);
    event DomainBidPlaced(string name, address bidder, uint256 bid);
    event DomainAuctionEnded(string name, address winner, uint256 finalBid);
    event DomainRented(string name, address renter, uint256 paid);
    event RentCompleted(string name, address newOwner);
    event RecoveryRequested(string name, address requester);
    event RecoveryApproved(string name, address newOwner);
    event ReputationUpdated(string name, uint256 newReputation);
    event SubdomainCreated(string mainDomain, string subDomain, address owner);
    event WebsiteUpdated(string name, string ipfsHash);

    modifier onlyOwner(string memory name) {
        require(nameToId[name] != 0, "Domain not registered");
        require(domains[nameToId[name]].owner == msg.sender, "Not domain owner");
        _;
    }

    function getRegistrationFee(string memory name) public pure returns (uint256) {
        uint256 length = bytes(name).length;
        require(length >= 3, "Domain name too short");

        if (length == 3) return 0.01 ether;
        if (length >= 4 && length <= 5) return 0.005 ether;
        if (length >= 6 && length <= 7) return 0.0015 ether;
        if (length >= 8 && length <= 10) return 0.001 ether;
        return 0.0005 ether;
    }

    function registerDomain(string memory name, uint256 rentTarget) public payable {
        require(nameToId[name] == 0, "Domain already taken");
        uint256 requiredFee = getRegistrationFee(name);
        require(msg.value >= requiredFee, "Insufficient registration fee");

        uint256 tokenId = nextId++;
        domains[tokenId] = Domain(name, msg.sender, block.timestamp + DURATION, false, 0, false, address(0), 0, rentTarget, 0, "");
        nameToId[name] = tokenId;
        nameToAddress[name] = msg.sender;

        emit DomainRegistered(name, msg.sender, block.timestamp + DURATION);
    }

    function renewDomain(string memory name) public payable onlyOwner(name) {
        uint256 renewalFee = (getRegistrationFee(name) * 75) / 100; // Discount 25%
        require(msg.value >= renewalFee, "Insufficient renewal fee");

        uint256 tokenId = nameToId[name];
        domains[tokenId].expiry += DURATION;

        emit DomainRenewed(name, domains[tokenId].expiry);
    }

    function transferDomain(string memory name, address to) public onlyOwner(name) {
        uint256 tokenId = nameToId[name];
        domains[tokenId].owner = to;
        nameToAddress[name] = to;

        emit DomainTransferred(name, msg.sender, to);
    }

    function startAuction(string memory name, uint256 minBid) public onlyOwner(name) {
        uint256 tokenId = nameToId[name];
        domains[tokenId].forAuction = true;
        domains[tokenId].minBid = minBid;

        emit DomainAuctionStarted(name, minBid);
    }

    function placeBid(string memory name) public payable {
        uint256 tokenId = nameToId[name];
        require(domains[tokenId].forAuction, "Domain not for auction");
        require(msg.value > auctionHighestBid[tokenId], "Bid too low");

        if (auctionHighestBid[tokenId] > 0) {
            payable(auctionHighestBidder[tokenId]).transfer(auctionHighestBid[tokenId]);
        }

        auctionHighestBidder[tokenId] = msg.sender;
        auctionHighestBid[tokenId] = msg.value;

        emit DomainBidPlaced(name, msg.sender, msg.value);
    }

    function endAuction(string memory name) public onlyOwner(name) {
        uint256 tokenId = nameToId[name];
        require(domains[tokenId].forAuction, "Domain not in auction");

        domains[tokenId].forAuction = false;
        domains[tokenId].owner = auctionHighestBidder[tokenId];
        nameToAddress[name] = auctionHighestBidder[tokenId];

        emit DomainAuctionEnded(name, auctionHighestBidder[tokenId], auctionHighestBid[tokenId]);
    }

    function rentDomain(string memory name) public payable {
        uint256 tokenId = nameToId[name];
        require(domains[tokenId].owner != address(0), "Domain not found");
        require(!domains[tokenId].isRented, "Already rented");
        require(msg.value > 0, "Need rent payment");

        domains[tokenId].isRented = true;
        domains[tokenId].renter = msg.sender;
        domains[tokenId].rentPaid += msg.value;

        emit DomainRented(name, msg.sender, msg.value);

        if (domains[tokenId].rentPaid >= domains[tokenId].rentTarget) {
            domains[tokenId].owner = msg.sender;
            domains[tokenId].isRented = false;
            emit RentCompleted(name, msg.sender);
        }
    }

    function addGuardian(address guardian) public {
        guardians[msg.sender].push(guardian);
    }

    function requestRecovery(string memory name) public {
        require(domains[nameToId[name]].owner == msg.sender, "Not owner");

        domainTrustees[name] = guardians[msg.sender];

        emit RecoveryRequested(name, msg.sender);
    }

    function approveRecovery(string memory name, address newOwner) public {
        require(isGuardian(msg.sender, name), "Not a guardian");
        require(domainTrustees[name].length >= 3, "Need at least 3 approvals");

        domains[nameToId[name]].owner = newOwner;
        emit RecoveryApproved(name, newOwner);
    }

    function isGuardian(address user, string memory name) internal view returns (bool) {
        for (uint256 i = 0; i < domainTrustees[name].length; i++) {
            if (domainTrustees[name][i] == user) {
                return true;
            }
        }
        return false;
    }

    function createSubdomain(string memory mainDomain, string memory subDomain, address owner) public onlyOwner(mainDomain) {
        require(subdomains[mainDomain][subDomain] == address(0), "Subdomain exists");

        subdomains[mainDomain][subDomain] = owner;

        emit SubdomainCreated(mainDomain, subDomain, owner);
    }
}
